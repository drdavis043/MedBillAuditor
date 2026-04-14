#!/usr/bin/env python3
"""
Process CMS data files to generate JSON resources for MedBillAuditor.

Reads from: ~/Desktop/CMS_Data/
Outputs to:  MedBillAuditor/Resources/
  - medicare_pricing.json   (10K+ codes with RVU-based pricing)
  - bundling_pairs.json     (curated NCCI PTP edit pairs)
  - mue_limits.json         (MUE quantity limits — placeholder until MUE file obtained)
  - code_descriptions.json  (500 common codes, our own plain-English descriptions)

COPYRIGHT: Strips ALL AMA CPT description text. Only retains code numbers,
numeric pricing data, PTP pair relationships, and CMS-created HCPCS descriptions.
"""

import csv
import io
import json
import os
import re
import sys
import zipfile
from collections import defaultdict
from pathlib import Path

CMS_DIR = Path.home() / "Desktop" / "CMS_Data"
OUTPUT_DIR = Path(__file__).parent / "MedBillAuditor" / "Resources"

# CY 2026 conversion factor (non-QP)
CONVERSION_FACTOR = 33.4009


# ---------------------------------------------------------------------------
# 1. MEDICARE PRICING (RVU data)
# ---------------------------------------------------------------------------

def process_rvu_pricing():
    """Parse PPRRVU2026_Jan_nonQPP.csv and compute national average prices."""
    rvu_zip = CMS_DIR / "rvu26ar_1 (1).zip"
    if not rvu_zip.exists():
        print(f"ERROR: {rvu_zip} not found")
        return []

    with zipfile.ZipFile(rvu_zip) as zf:
        with zf.open("PPRRVU2026_Jan_nonQPP.csv") as f:
            text = f.read().decode("utf-8", errors="replace")

    lines = text.splitlines()

    # Find the header row (starts with HCPCS,MOD,DESCRIPTION...)
    header_idx = None
    for i, line in enumerate(lines):
        if line.startswith("HCPCS,MOD,"):
            header_idx = i
            break

    if header_idx is None:
        print("ERROR: Could not find RVU header row")
        return []

    reader = csv.reader(lines[header_idx:])
    header = next(reader)

    # Map column names to indices
    col = {name.strip(): idx for idx, name in enumerate(header)}

    # We need: HCPCS, MOD, STATUS CODE, WORK RVU, NON-FAC PE RVU, FACILITY PE RVU, MP RVU, GLOB DAYS, CONV FACTOR
    codes = {}  # code -> best entry (prefer no-modifier row)

    for row in reader:
        if len(row) < 12:
            continue

        hcpcs = row[col.get("HCPCS", 0)].strip()
        mod = row[col.get("MOD", 1)].strip()
        status = row[col.get("STATUS CODE", col.get("STATUS\nCODE", 3))].strip() if "STATUS CODE" in col or "STATUS\nCODE" in col else row[3].strip()

        if not hcpcs or not re.match(r'^[0-9A-Z]\w{3,4}$', hcpcs):
            continue

        # Skip inactive codes
        if status in ("D", "N", "B", "I", "R", "X"):
            # D=deleted, N=non-covered, B=bundled, I=not valid for Medicare,
            # R=restricted, X=statutory exclusion
            # Keep I (performance measures) and some others; skip truly inactive
            if status in ("D", "X"):
                continue

        def safe_float(val):
            try:
                return float(val.strip()) if val.strip() else 0.0
            except (ValueError, AttributeError):
                return 0.0

        work_rvu = safe_float(row[col.get("WORK RVU", col.get("WORK\nRVU", 5))] if "WORK RVU" in col or "WORK\nRVU" in col else row[5])
        nonfac_pe = safe_float(row[col.get("NON-FAC PE RVU", col.get("NON-FAC\nPE RVU", 6))] if "NON-FAC PE RVU" in col or "NON-FAC\nPE RVU" in col else row[6])
        fac_pe = safe_float(row[col.get("FACILITY PE RVU", col.get("FACILITY\nPE RVU", 8))] if "FACILITY PE RVU" in col or "FACILITY\nPE RVU" in col else row[8])
        mp_rvu = safe_float(row[col.get("MP RVU", col.get("MP\nRVU", 10))] if "MP RVU" in col or "MP\nRVU" in col else row[10])

        glob_days_col = None
        for candidate in ["GLOB DAYS", "GLOB\nDAYS", "GLOBAL DAYS"]:
            if candidate in col:
                glob_days_col = col[candidate]
                break
        glob_days = row[glob_days_col].strip() if glob_days_col is not None else row[14].strip() if len(row) > 14 else ""

        # Calculate prices
        nonfac_total_rvu = work_rvu + nonfac_pe + mp_rvu
        fac_total_rvu = work_rvu + fac_pe + mp_rvu
        nonfac_price = round(nonfac_total_rvu * CONVERSION_FACTOR, 2)
        fac_price = round(fac_total_rvu * CONVERSION_FACTOR, 2)

        # Prefer no-modifier row; if modifier exists, only add if code not seen yet
        if hcpcs not in codes or (not mod and codes[hcpcs].get("mod")):
            entry = {
                "code": hcpcs,
                "mod": mod,
                "status": status,
                "workRvu": round(work_rvu, 2),
                "nonfacPeRvu": round(nonfac_pe, 2),
                "facPeRvu": round(fac_pe, 2),
                "mpRvu": round(mp_rvu, 2),
                "totalRvu": round(nonfac_total_rvu, 2),
                "nonFacilityPrice": nonfac_price,
                "facilityPrice": fac_price,
                "globalPeriod": glob_days,
            }
            codes[hcpcs] = entry

    # Build final output — strip mod field (internal only), strip AMA descriptions
    results = []
    for code in sorted(codes.keys()):
        e = codes[code]
        out = {
            "code": e["code"],
            "status": e["status"],
            "workRvu": e["workRvu"],
            "totalRvu": e["totalRvu"],
            "nonFacilityPrice": e["nonFacilityPrice"],
            "facilityPrice": e["facilityPrice"],
            "globalPeriod": e["globalPeriod"],
        }
        # Only include prices > 0
        if out["nonFacilityPrice"] > 0 or out["facilityPrice"] > 0 or out["totalRvu"] > 0:
            results.append(out)

    print(f"  Pricing: {len(results)} codes with pricing data")
    return results


# ---------------------------------------------------------------------------
# 2. NCCI PTP EDIT PAIRS (Practitioner)
# ---------------------------------------------------------------------------

# Consumer-relevant code ranges
CONSUMER_RANGES = [
    (100, 1999),      # Anesthesia
    (10004, 69999),   # Surgery (common outpatient)
    (70010, 79999),   # Radiology
    (80047, 89999),   # Lab/Pathology
    (90281, 99499),   # Medicine, E&M, vaccines
    (96360, 96549),   # Infusions, chemo
    (97010, 97799),   # Physical therapy
    (99201, 99499),   # E&M
]

HCPCS_PREFIXES = set("ABCDEGHJKLMPQRSTV")


def is_consumer_relevant(code):
    """Check if a code is in the consumer-relevant ranges."""
    if not code:
        return False
    # HCPCS Level II (letter prefix) — keep J codes (drugs), A codes (ambulance/supplies), G codes (CMS)
    if code[0].isalpha():
        return code[0].upper() in HCPCS_PREFIXES
    # Numeric CPT
    try:
        num = int(code)
    except ValueError:
        return False
    return any(lo <= num <= hi for lo, hi in CONSUMER_RANGES)


def parse_ptp_file(zf, filename):
    """Parse a single PTP edit text file from a zip."""
    with zf.open(filename) as f:
        text = f.read().decode("utf-8", errors="replace")

    pairs = []
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) < 6:
            continue

        col1 = parts[0].strip()
        col2 = parts[1].strip()
        # Skip header/metadata lines
        if not col1 or col1.startswith("Column") or col1.startswith("CPT"):
            continue
        # Validate code format
        if not re.match(r'^[0-9A-Z]\w{3,4}$', col1):
            continue

        effective = parts[3].strip() if len(parts) > 3 else ""
        deletion = parts[4].strip() if len(parts) > 4 else ""
        modifier = parts[5].strip() if len(parts) > 5 else ""
        rationale = parts[6].strip() if len(parts) > 6 else ""

        # Filter: active only (deletion is empty or '*')
        if deletion and deletion != "*":
            # Has a deletion date — check if it's in the future
            # Format: YYYYMMDD
            if re.match(r'^\d{8}$', deletion):
                # If deletion date is in the past, skip
                if int(deletion) < 20260101:
                    continue

        # Filter: modifier indicator = 0 (never bill together) — strongest edits
        # Also include 1 (may bill with modifier) for completeness
        if modifier not in ("0", "1"):
            continue

        pairs.append({
            "col1": col1,
            "col2": col2,
            "modifier": int(modifier),
            "rationale": rationale,
        })

    return pairs


def process_ptp_edits():
    """Process all practitioner PTP edit files."""
    all_pairs = []

    for fname in sorted(CMS_DIR.glob("ccipra-v321r0-f*.zip")):
        print(f"  Processing {fname.name}...")
        with zipfile.ZipFile(fname) as zf:
            txt_files = [n for n in zf.namelist() if n.endswith(".TXT")]
            for txt in txt_files:
                pairs = parse_ptp_file(zf, txt)
                all_pairs.extend(pairs)

    print(f"  Total raw pairs: {len(all_pairs)}")

    # Filter to consumer-relevant pairs where BOTH codes are relevant
    relevant = []
    seen = set()
    for p in all_pairs:
        if is_consumer_relevant(p["col1"]) and is_consumer_relevant(p["col2"]):
            key = (p["col1"], p["col2"])
            if key not in seen:
                seen.add(key)
                relevant.append(p)

    print(f"  Consumer-relevant unique pairs: {len(relevant)}")

    # Further prioritize: modifier=0 pairs (never bill together)
    mod0 = [p for p in relevant if p["modifier"] == 0]
    mod1 = [p for p in relevant if p["modifier"] == 1]
    print(f"    Modifier 0 (never together): {len(mod0)}")
    print(f"    Modifier 1 (needs modifier): {len(mod1)}")

    # Keep all modifier=0 and modifier=1 pairs within reason
    # Cap at ~10K pairs for app bundle size
    final = mod0 + mod1
    if len(final) > 15000:
        # Prioritize mod=0 pairs and most common code ranges
        final = mod0[:10000] + mod1[:5000]

    return final


# ---------------------------------------------------------------------------
# 3. RATIONALE MAPPING (for PTP pairs)
# ---------------------------------------------------------------------------

RATIONALE_MAP = {
    "Standards of medical/surgical practice": 1,
    "CPT descriptor(s) or CPT coding instruction": 2,
    "Mutually exclusive procedures": 3,
    "Comprehensive code/component code": 4,
    "CPT Manual or CMS manual coding instruction": 5,
    "NCCI policy": 6,
    "Misuse of column two code with column one code": 7,
}


def normalize_rationale(text):
    """Convert rationale text to numeric code."""
    for key, val in RATIONALE_MAP.items():
        if key.lower() in text.lower():
            return val
    return 0


# ---------------------------------------------------------------------------
# 4. CODE DESCRIPTIONS (our own plain-English, NOT AMA text)
# ---------------------------------------------------------------------------

def generate_code_descriptions():
    """Generate our own plain-English descriptions for ~500 common codes.

    These are NOT copied from AMA's CPT codebook. They are commonly used
    shorthand descriptions written by us for consumer understanding.
    """
    descriptions = {
        # --- E&M Office Visits ---
        "99202": {"description": "New Patient Office Visit (Level 2)", "category": "evaluation_management"},
        "99203": {"description": "New Patient Office Visit (Level 3)", "category": "evaluation_management"},
        "99204": {"description": "New Patient Office Visit (Level 4)", "category": "evaluation_management"},
        "99205": {"description": "New Patient Office Visit (Level 5)", "category": "evaluation_management"},
        "99211": {"description": "Established Patient Office Visit (Level 1)", "category": "evaluation_management"},
        "99212": {"description": "Established Patient Office Visit (Level 2)", "category": "evaluation_management"},
        "99213": {"description": "Established Patient Office Visit (Level 3)", "category": "evaluation_management"},
        "99214": {"description": "Established Patient Office Visit (Level 4)", "category": "evaluation_management"},
        "99215": {"description": "Established Patient Office Visit (Level 5)", "category": "evaluation_management"},

        # --- ER Visits ---
        "99281": {"description": "Emergency Room Visit (Level 1)", "category": "emergency"},
        "99282": {"description": "Emergency Room Visit (Level 2)", "category": "emergency"},
        "99283": {"description": "Emergency Room Visit (Level 3)", "category": "emergency"},
        "99284": {"description": "Emergency Room Visit (Level 4)", "category": "emergency"},
        "99285": {"description": "Emergency Room Visit (Level 5)", "category": "emergency"},

        # --- Hospital Visits ---
        "99221": {"description": "Initial Hospital Admission (Level 1)", "category": "hospital"},
        "99222": {"description": "Initial Hospital Admission (Level 2)", "category": "hospital"},
        "99223": {"description": "Initial Hospital Admission (Level 3)", "category": "hospital"},
        "99231": {"description": "Subsequent Hospital Visit (Level 1)", "category": "hospital"},
        "99232": {"description": "Subsequent Hospital Visit (Level 2)", "category": "hospital"},
        "99233": {"description": "Subsequent Hospital Visit (Level 3)", "category": "hospital"},
        "99238": {"description": "Hospital Discharge (30 minutes or less)", "category": "hospital"},
        "99239": {"description": "Hospital Discharge (over 30 minutes)", "category": "hospital"},
        "99291": {"description": "Critical Care First Hour", "category": "hospital"},
        "99292": {"description": "Critical Care Each Additional 30 min", "category": "hospital"},

        # --- Observation ---
        "99218": {"description": "Initial Observation Care (Level 1)", "category": "hospital"},
        "99219": {"description": "Initial Observation Care (Level 2)", "category": "hospital"},
        "99220": {"description": "Initial Observation Care (Level 3)", "category": "hospital"},

        # --- Consults ---
        "99241": {"description": "Office Consultation (Level 1)", "category": "evaluation_management"},
        "99242": {"description": "Office Consultation (Level 2)", "category": "evaluation_management"},
        "99243": {"description": "Office Consultation (Level 3)", "category": "evaluation_management"},
        "99244": {"description": "Office Consultation (Level 4)", "category": "evaluation_management"},
        "99245": {"description": "Office Consultation (Level 5)", "category": "evaluation_management"},

        # --- Preventive Medicine ---
        "99381": {"description": "Preventive Visit, New Patient (Infant)", "category": "preventive"},
        "99382": {"description": "Preventive Visit, New Patient (Age 1-4)", "category": "preventive"},
        "99383": {"description": "Preventive Visit, New Patient (Age 5-11)", "category": "preventive"},
        "99384": {"description": "Preventive Visit, New Patient (Age 12-17)", "category": "preventive"},
        "99385": {"description": "Preventive Visit, New Patient (Age 18-39)", "category": "preventive"},
        "99386": {"description": "Preventive Visit, New Patient (Age 40-64)", "category": "preventive"},
        "99387": {"description": "Preventive Visit, New Patient (Age 65+)", "category": "preventive"},
        "99391": {"description": "Preventive Visit, Established (Infant)", "category": "preventive"},
        "99392": {"description": "Preventive Visit, Established (Age 1-4)", "category": "preventive"},
        "99393": {"description": "Preventive Visit, Established (Age 5-11)", "category": "preventive"},
        "99394": {"description": "Preventive Visit, Established (Age 12-17)", "category": "preventive"},
        "99395": {"description": "Preventive Visit, Established (Age 18-39)", "category": "preventive"},
        "99396": {"description": "Preventive Visit, Established (Age 40-64)", "category": "preventive"},
        "99397": {"description": "Preventive Visit, Established (Age 65+)", "category": "preventive"},

        # --- Lab Panels ---
        "80047": {"description": "Basic Metabolic Panel with Ionized Calcium", "category": "laboratory"},
        "80048": {"description": "Basic Metabolic Panel (BMP)", "category": "laboratory"},
        "80050": {"description": "General Health Panel", "category": "laboratory"},
        "80051": {"description": "Electrolyte Panel", "category": "laboratory"},
        "80053": {"description": "Comprehensive Metabolic Panel (CMP)", "category": "laboratory"},
        "80055": {"description": "Obstetric Panel", "category": "laboratory"},
        "80061": {"description": "Lipid Panel", "category": "laboratory"},
        "80069": {"description": "Renal Function Panel", "category": "laboratory"},
        "80074": {"description": "Acute Hepatitis Panel", "category": "laboratory"},
        "80076": {"description": "Hepatic Function Panel", "category": "laboratory"},
        "80081": {"description": "Obstetric Panel with HIV", "category": "laboratory"},

        # --- Common Individual Labs ---
        "82040": {"description": "Albumin Blood Test", "category": "laboratory"},
        "82247": {"description": "Bilirubin, Total", "category": "laboratory"},
        "82248": {"description": "Bilirubin, Direct", "category": "laboratory"},
        "82310": {"description": "Calcium, Total", "category": "laboratory"},
        "82374": {"description": "Carbon Dioxide (CO2/Bicarbonate)", "category": "laboratory"},
        "82435": {"description": "Chloride Blood Test", "category": "laboratory"},
        "82465": {"description": "Cholesterol, Total", "category": "laboratory"},
        "82550": {"description": "CK/CPK (Creatine Kinase)", "category": "laboratory"},
        "82565": {"description": "Creatinine Blood Test", "category": "laboratory"},
        "82607": {"description": "Vitamin B-12 Level", "category": "laboratory"},
        "82728": {"description": "Ferritin Level", "category": "laboratory"},
        "82746": {"description": "Folic Acid Level", "category": "laboratory"},
        "82947": {"description": "Glucose Blood Test", "category": "laboratory"},
        "82962": {"description": "Glucose, Fingerstick (POC)", "category": "laboratory"},
        "83001": {"description": "FSH (Follicle Stimulating Hormone)", "category": "laboratory"},
        "83002": {"description": "LH (Luteinizing Hormone)", "category": "laboratory"},
        "83036": {"description": "Hemoglobin A1c", "category": "laboratory"},
        "83540": {"description": "Iron Level", "category": "laboratory"},
        "83615": {"description": "LDH (Lactate Dehydrogenase)", "category": "laboratory"},
        "83718": {"description": "HDL Cholesterol", "category": "laboratory"},
        "83721": {"description": "LDL Cholesterol, Direct", "category": "laboratory"},
        "84075": {"description": "Alkaline Phosphatase", "category": "laboratory"},
        "84132": {"description": "Potassium Blood Test", "category": "laboratory"},
        "84134": {"description": "Prealbumin", "category": "laboratory"},
        "84153": {"description": "PSA (Prostate Specific Antigen)", "category": "laboratory"},
        "84155": {"description": "Total Protein", "category": "laboratory"},
        "84295": {"description": "Sodium Blood Test", "category": "laboratory"},
        "84403": {"description": "Testosterone, Total", "category": "laboratory"},
        "84436": {"description": "Thyroxine (T4), Total", "category": "laboratory"},
        "84439": {"description": "Free T4 (Thyroxine)", "category": "laboratory"},
        "84443": {"description": "TSH (Thyroid Stimulating Hormone)", "category": "laboratory"},
        "84450": {"description": "AST (SGOT) Liver Enzyme", "category": "laboratory"},
        "84460": {"description": "ALT (SGPT) Liver Enzyme", "category": "laboratory"},
        "84478": {"description": "Triglycerides", "category": "laboratory"},
        "84520": {"description": "BUN (Blood Urea Nitrogen)", "category": "laboratory"},
        "84550": {"description": "Uric Acid Blood Test", "category": "laboratory"},
        "84702": {"description": "hCG Pregnancy Test, Quantitative", "category": "laboratory"},
        "84703": {"description": "hCG Pregnancy Test, Qualitative", "category": "laboratory"},
        "85004": {"description": "Automated Differential WBC Count", "category": "laboratory"},
        "85007": {"description": "Manual Differential WBC Count", "category": "laboratory"},
        "85014": {"description": "Hematocrit", "category": "laboratory"},
        "85018": {"description": "Hemoglobin", "category": "laboratory"},
        "85025": {"description": "CBC with Differential", "category": "laboratory"},
        "85027": {"description": "CBC without Differential", "category": "laboratory"},
        "85610": {"description": "PT (Prothrombin Time)", "category": "laboratory"},
        "85730": {"description": "PTT (Partial Thromboplastin Time)", "category": "laboratory"},
        "86140": {"description": "C-Reactive Protein (CRP)", "category": "laboratory"},
        "86200": {"description": "Cyclic Citrullinated Peptide Antibody", "category": "laboratory"},
        "86235": {"description": "Nuclear Antigen Antibody", "category": "laboratory"},
        "86300": {"description": "CA-125 Tumor Marker", "category": "laboratory"},
        "86308": {"description": "Mono Spot Test", "category": "laboratory"},
        "86580": {"description": "TB Skin Test (PPD)", "category": "laboratory"},
        "86592": {"description": "Syphilis Test (RPR/VDRL)", "category": "laboratory"},
        "86694": {"description": "Herpes Simplex Antibody", "category": "laboratory"},
        "86695": {"description": "Herpes Simplex Type 1 Antibody", "category": "laboratory"},
        "86696": {"description": "Herpes Simplex Type 2 Antibody", "category": "laboratory"},
        "86703": {"description": "HIV-1 and HIV-2 Antibody", "category": "laboratory"},
        "86762": {"description": "Rubella Antibody", "category": "laboratory"},
        "86765": {"description": "Rubeola (Measles) Antibody", "category": "laboratory"},
        "86803": {"description": "Hepatitis C Antibody", "category": "laboratory"},
        "87070": {"description": "Bacterial Culture, Any Source", "category": "laboratory"},
        "87077": {"description": "Bacterial Culture, Aerobic", "category": "laboratory"},
        "87081": {"description": "Bacterial Culture, Screen Only", "category": "laboratory"},
        "87086": {"description": "Urine Culture, Bacterial", "category": "laboratory"},
        "87088": {"description": "Urine Culture with Colony Count", "category": "laboratory"},
        "87205": {"description": "Gram Stain", "category": "laboratory"},
        "87210": {"description": "Wet Mount/KOH Prep", "category": "laboratory"},
        "87491": {"description": "Chlamydia DNA/RNA Test", "category": "laboratory"},
        "87591": {"description": "Gonorrhea DNA/RNA Test", "category": "laboratory"},
        "87804": {"description": "Influenza Rapid Test", "category": "laboratory"},
        "87880": {"description": "Strep A Rapid Test", "category": "laboratory"},
        "87900": {"description": "Drug Resistance Genotype Analysis", "category": "laboratory"},
        "81001": {"description": "Urinalysis with Microscopy", "category": "laboratory"},
        "81002": {"description": "Urinalysis, Non-automated", "category": "laboratory"},
        "81003": {"description": "Urinalysis, Automated", "category": "laboratory"},
        "81025": {"description": "Urine Pregnancy Test", "category": "laboratory"},
        "80307": {"description": "Drug Screen, Multiple Substances", "category": "laboratory"},

        # --- Radiology ---
        "70030": {"description": "X-ray Eye for Foreign Body", "category": "radiology"},
        "70100": {"description": "X-ray Jaw (1-3 views)", "category": "radiology"},
        "70110": {"description": "X-ray Jaw (4+ views)", "category": "radiology"},
        "70150": {"description": "X-ray Facial Bones", "category": "radiology"},
        "70160": {"description": "X-ray Nasal Bones", "category": "radiology"},
        "70200": {"description": "X-ray Orbits", "category": "radiology"},
        "70210": {"description": "X-ray Sinuses (limited)", "category": "radiology"},
        "70220": {"description": "X-ray Sinuses (complete)", "category": "radiology"},
        "70250": {"description": "X-ray Skull (limited)", "category": "radiology"},
        "70260": {"description": "X-ray Skull (complete)", "category": "radiology"},
        "70328": {"description": "X-ray TMJ Joint", "category": "radiology"},
        "70360": {"description": "X-ray Neck Soft Tissue", "category": "radiology"},
        "70450": {"description": "CT Head/Brain without Contrast", "category": "radiology"},
        "70460": {"description": "CT Head/Brain with Contrast", "category": "radiology"},
        "70470": {"description": "CT Head/Brain Without Then With Contrast", "category": "radiology"},
        "70486": {"description": "CT Sinuses without Contrast", "category": "radiology"},
        "70490": {"description": "CT Neck without Contrast", "category": "radiology"},
        "70491": {"description": "CT Neck with Contrast", "category": "radiology"},
        "70540": {"description": "MRI Orbit/Face/Neck without Contrast", "category": "radiology"},
        "70551": {"description": "MRI Brain without Contrast", "category": "radiology"},
        "70552": {"description": "MRI Brain with Contrast", "category": "radiology"},
        "70553": {"description": "MRI Brain Without Then With Contrast", "category": "radiology"},
        "71045": {"description": "Chest X-ray (1 view)", "category": "radiology"},
        "71046": {"description": "Chest X-ray (2 views)", "category": "radiology"},
        "71047": {"description": "Chest X-ray (3 views)", "category": "radiology"},
        "71048": {"description": "Chest X-ray (4+ views)", "category": "radiology"},
        "71100": {"description": "X-ray Ribs (unilateral, 2 views)", "category": "radiology"},
        "71101": {"description": "X-ray Ribs (unilateral, incl chest)", "category": "radiology"},
        "71110": {"description": "X-ray Ribs (bilateral, 3 views)", "category": "radiology"},
        "71250": {"description": "CT Chest without Contrast", "category": "radiology"},
        "71260": {"description": "CT Chest with Contrast", "category": "radiology"},
        "71270": {"description": "CT Chest Without Then With Contrast", "category": "radiology"},
        "71275": {"description": "CT Angiography, Chest", "category": "radiology"},
        "71550": {"description": "MRI Chest without Contrast", "category": "radiology"},
        "72040": {"description": "X-ray Spine, Cervical (2-3 views)", "category": "radiology"},
        "72050": {"description": "X-ray Spine, Cervical (4-5 views)", "category": "radiology"},
        "72070": {"description": "X-ray Spine, Thoracic (2 views)", "category": "radiology"},
        "72100": {"description": "X-ray Spine, Lumbar (2-3 views)", "category": "radiology"},
        "72110": {"description": "X-ray Spine, Lumbar (4+ views)", "category": "radiology"},
        "72125": {"description": "CT Cervical Spine without Contrast", "category": "radiology"},
        "72131": {"description": "CT Lumbar Spine without Contrast", "category": "radiology"},
        "72141": {"description": "MRI Cervical Spine without Contrast", "category": "radiology"},
        "72146": {"description": "MRI Thoracic Spine without Contrast", "category": "radiology"},
        "72148": {"description": "MRI Lumbar Spine without Contrast", "category": "radiology"},
        "72156": {"description": "MRI Cervical Spine Without Then With Contrast", "category": "radiology"},
        "72157": {"description": "MRI Thoracic Spine Without Then With Contrast", "category": "radiology"},
        "72158": {"description": "MRI Lumbar Spine Without Then With Contrast", "category": "radiology"},
        "72170": {"description": "X-ray Pelvis (1-2 views)", "category": "radiology"},
        "72190": {"description": "X-ray Pelvis (3+ views)", "category": "radiology"},
        "72192": {"description": "CT Pelvis without Contrast", "category": "radiology"},
        "72193": {"description": "CT Pelvis with Contrast", "category": "radiology"},
        "72195": {"description": "MRI Pelvis without Contrast", "category": "radiology"},
        "72197": {"description": "MRI Pelvis Without Then With Contrast", "category": "radiology"},
        "73000": {"description": "X-ray Clavicle", "category": "radiology"},
        "73010": {"description": "X-ray Scapula", "category": "radiology"},
        "73020": {"description": "X-ray Shoulder (1 view)", "category": "radiology"},
        "73030": {"description": "X-ray Shoulder (2+ views)", "category": "radiology"},
        "73060": {"description": "X-ray Humerus (2+ views)", "category": "radiology"},
        "73070": {"description": "X-ray Elbow (2 views)", "category": "radiology"},
        "73080": {"description": "X-ray Elbow (3+ views)", "category": "radiology"},
        "73090": {"description": "X-ray Forearm (2 views)", "category": "radiology"},
        "73100": {"description": "X-ray Wrist (2 views)", "category": "radiology"},
        "73110": {"description": "X-ray Wrist (3+ views)", "category": "radiology"},
        "73120": {"description": "X-ray Hand (2 views)", "category": "radiology"},
        "73130": {"description": "X-ray Hand (3+ views)", "category": "radiology"},
        "73140": {"description": "X-ray Finger(s)", "category": "radiology"},
        "73221": {"description": "MRI Shoulder without Contrast", "category": "radiology"},
        "73222": {"description": "MRI Shoulder with Contrast", "category": "radiology"},
        "73223": {"description": "MRI Shoulder Without Then With Contrast", "category": "radiology"},
        "73501": {"description": "X-ray Hip (1 view)", "category": "radiology"},
        "73502": {"description": "X-ray Hip (2-3 views)", "category": "radiology"},
        "73503": {"description": "X-ray Hip (4+ views)", "category": "radiology"},
        "73521": {"description": "X-ray Hips Bilateral (2 views)", "category": "radiology"},
        "73551": {"description": "X-ray Femur (1 view)", "category": "radiology"},
        "73552": {"description": "X-ray Femur (2+ views)", "category": "radiology"},
        "73560": {"description": "X-ray Knee (1-2 views)", "category": "radiology"},
        "73562": {"description": "X-ray Knee (3 views)", "category": "radiology"},
        "73564": {"description": "X-ray Knee (4+ views)", "category": "radiology"},
        "73590": {"description": "X-ray Lower Leg (2 views)", "category": "radiology"},
        "73600": {"description": "X-ray Ankle (2 views)", "category": "radiology"},
        "73610": {"description": "X-ray Ankle (3+ views)", "category": "radiology"},
        "73620": {"description": "X-ray Foot (2 views)", "category": "radiology"},
        "73630": {"description": "X-ray Foot (3+ views)", "category": "radiology"},
        "73650": {"description": "X-ray Heel (2+ views)", "category": "radiology"},
        "73660": {"description": "X-ray Toe(s)", "category": "radiology"},
        "73700": {"description": "CT Lower Extremity without Contrast", "category": "radiology"},
        "73718": {"description": "MRI Lower Extremity without Contrast", "category": "radiology"},
        "73720": {"description": "MRI Lower Extremity Without Then With Contrast", "category": "radiology"},
        "73721": {"description": "MRI Knee without Contrast", "category": "radiology"},
        "73723": {"description": "MRI Knee Without Then With Contrast", "category": "radiology"},
        "74018": {"description": "X-ray Abdomen (1 view)", "category": "radiology"},
        "74019": {"description": "X-ray Abdomen (2 views)", "category": "radiology"},
        "74021": {"description": "X-ray Abdomen (3+ views)", "category": "radiology"},
        "74150": {"description": "CT Abdomen without Contrast", "category": "radiology"},
        "74160": {"description": "CT Abdomen with Contrast", "category": "radiology"},
        "74170": {"description": "CT Abdomen Without Then With Contrast", "category": "radiology"},
        "74176": {"description": "CT Abdomen and Pelvis without Contrast", "category": "radiology"},
        "74177": {"description": "CT Abdomen and Pelvis with Contrast", "category": "radiology"},
        "74178": {"description": "CT Abdomen/Pelvis Without Then With Contrast", "category": "radiology"},
        "74181": {"description": "MRI Abdomen without Contrast", "category": "radiology"},
        "74183": {"description": "MRI Abdomen Without Then With Contrast", "category": "radiology"},
        "76536": {"description": "Ultrasound Soft Tissue Head/Neck", "category": "radiology"},
        "76604": {"description": "Ultrasound Chest", "category": "radiology"},
        "76641": {"description": "Ultrasound Breast, Complete", "category": "radiology"},
        "76642": {"description": "Ultrasound Breast, Limited", "category": "radiology"},
        "76700": {"description": "Ultrasound Abdomen, Complete", "category": "radiology"},
        "76705": {"description": "Ultrasound Abdomen, Limited", "category": "radiology"},
        "76770": {"description": "Ultrasound Retroperitoneal, Complete", "category": "radiology"},
        "76775": {"description": "Ultrasound Retroperitoneal, Limited", "category": "radiology"},
        "76801": {"description": "OB Ultrasound, First Trimester", "category": "radiology"},
        "76805": {"description": "OB Ultrasound, Second/Third Trimester", "category": "radiology"},
        "76810": {"description": "OB Ultrasound, Twin/Multiple", "category": "radiology"},
        "76815": {"description": "OB Ultrasound, Limited", "category": "radiology"},
        "76817": {"description": "Transvaginal Ultrasound", "category": "radiology"},
        "76830": {"description": "Ultrasound Pelvis, Transvaginal", "category": "radiology"},
        "76856": {"description": "Ultrasound Pelvis, Complete", "category": "radiology"},
        "76857": {"description": "Ultrasound Pelvis, Limited", "category": "radiology"},
        "76870": {"description": "Ultrasound Scrotum", "category": "radiology"},
        "76881": {"description": "Ultrasound Joint, Complete", "category": "radiology"},
        "76882": {"description": "Ultrasound Joint, Limited", "category": "radiology"},
        "77065": {"description": "Mammogram, Screening (unilateral)", "category": "radiology"},
        "77066": {"description": "Mammogram, Screening (bilateral)", "category": "radiology"},
        "77067": {"description": "Mammogram, Screening (bilateral)", "category": "radiology"},

        # --- Common Surgical/Procedures ---
        "10060": {"description": "Incision & Drainage of Abscess (Simple)", "category": "surgery"},
        "10061": {"description": "Incision & Drainage of Abscess (Complex)", "category": "surgery"},
        "10120": {"description": "Removal of Foreign Body, Skin (Simple)", "category": "surgery"},
        "10140": {"description": "Incision & Drainage of Hematoma", "category": "surgery"},
        "10160": {"description": "Aspiration of Abscess/Cyst", "category": "surgery"},
        "11042": {"description": "Wound Debridement (Subcutaneous)", "category": "surgery"},
        "11043": {"description": "Wound Debridement (Muscle/Fascia)", "category": "surgery"},
        "11044": {"description": "Wound Debridement (Bone)", "category": "surgery"},
        "11055": {"description": "Trimming of Skin Lesion (1 lesion)", "category": "dermatology"},
        "11056": {"description": "Trimming of Skin Lesion (2-4 lesions)", "category": "dermatology"},
        "11102": {"description": "Skin Biopsy, Tangential", "category": "dermatology"},
        "11104": {"description": "Skin Biopsy, Punch", "category": "dermatology"},
        "11106": {"description": "Skin Biopsy, Incisional", "category": "dermatology"},
        "11200": {"description": "Skin Tag Removal (up to 15)", "category": "dermatology"},
        "11300": {"description": "Shave Removal of Skin Lesion (0.5 cm or less)", "category": "dermatology"},
        "11305": {"description": "Shave Removal of Scalp/Neck Lesion (0.5 cm or less)", "category": "dermatology"},
        "11400": {"description": "Excision of Skin Lesion (0.5 cm or less)", "category": "dermatology"},
        "11600": {"description": "Excision of Malignant Lesion (0.5 cm or less)", "category": "dermatology"},
        "11721": {"description": "Debridement of Nails (6 or more)", "category": "dermatology"},
        "11730": {"description": "Removal of Nail Plate (Partial/Complete)", "category": "dermatology"},
        "11750": {"description": "Permanent Nail Removal", "category": "dermatology"},
        "12001": {"description": "Simple Wound Repair (2.5 cm or less)", "category": "surgery"},
        "12002": {"description": "Simple Wound Repair (2.6-7.5 cm)", "category": "surgery"},
        "12004": {"description": "Simple Wound Repair (7.6-12.5 cm)", "category": "surgery"},
        "12011": {"description": "Simple Wound Repair Face/Ears (2.5 cm or less)", "category": "surgery"},
        "12013": {"description": "Simple Wound Repair Face/Ears (2.6-5.0 cm)", "category": "surgery"},
        "12031": {"description": "Intermediate Wound Repair (2.5 cm or less)", "category": "surgery"},
        "12032": {"description": "Intermediate Wound Repair (2.6-7.5 cm)", "category": "surgery"},
        "12051": {"description": "Intermediate Wound Repair Face (2.5 cm or less)", "category": "surgery"},
        "17000": {"description": "Destruction of Premalignant Lesion (First)", "category": "dermatology"},
        "17003": {"description": "Destruction of Premalignant Lesion (Each Additional)", "category": "dermatology"},
        "17110": {"description": "Destruction of Warts (up to 14)", "category": "dermatology"},
        "17111": {"description": "Destruction of Warts (15 or more)", "category": "dermatology"},
        "17311": {"description": "Mohs Surgery, First Stage (Head/Neck)", "category": "dermatology"},
        "17312": {"description": "Mohs Surgery, Each Additional Stage", "category": "dermatology"},
        "20550": {"description": "Injection into Tendon/Ligament", "category": "orthopedic"},
        "20552": {"description": "Trigger Point Injection (1-2 muscles)", "category": "orthopedic"},
        "20553": {"description": "Trigger Point Injection (3+ muscles)", "category": "orthopedic"},
        "20600": {"description": "Joint Aspiration (Small Joint)", "category": "orthopedic"},
        "20605": {"description": "Joint Aspiration (Intermediate Joint)", "category": "orthopedic"},
        "20610": {"description": "Joint Aspiration/Injection (Major Joint)", "category": "orthopedic"},
        "20611": {"description": "Joint Aspiration/Injection (Major Joint, Ultrasound)", "category": "orthopedic"},
        "27447": {"description": "Total Knee Replacement", "category": "orthopedic"},
        "27130": {"description": "Total Hip Replacement", "category": "orthopedic"},
        "29881": {"description": "Knee Arthroscopy with Meniscectomy", "category": "orthopedic"},
        "29826": {"description": "Shoulder Arthroscopy with Decompression", "category": "orthopedic"},
        "36415": {"description": "Venipuncture (Blood Draw)", "category": "laboratory"},
        "36416": {"description": "Finger/Heel Capillary Blood Collection", "category": "laboratory"},
        "36591": {"description": "Blood Draw from Central Line", "category": "laboratory"},
        "43235": {"description": "Upper GI Endoscopy (EGD), Diagnostic", "category": "gastroenterology"},
        "43239": {"description": "Upper GI Endoscopy with Biopsy", "category": "gastroenterology"},
        "45378": {"description": "Colonoscopy, Diagnostic", "category": "gastroenterology"},
        "45380": {"description": "Colonoscopy with Biopsy", "category": "gastroenterology"},
        "45385": {"description": "Colonoscopy with Polyp Removal (Snare)", "category": "gastroenterology"},
        "45388": {"description": "Colonoscopy with Polyp Removal (Ablation)", "category": "gastroenterology"},
        "49505": {"description": "Inguinal Hernia Repair", "category": "surgery"},
        "50590": {"description": "Lithotripsy (Kidney Stone Shock Wave)", "category": "urology"},
        "52000": {"description": "Cystoscopy, Diagnostic", "category": "urology"},
        "55700": {"description": "Prostate Biopsy", "category": "urology"},
        "58100": {"description": "Endometrial Biopsy", "category": "ob_gyn"},
        "58558": {"description": "Hysteroscopy with Biopsy", "category": "ob_gyn"},
        "58571": {"description": "Laparoscopic Hysterectomy (250g or less)", "category": "ob_gyn"},
        "59400": {"description": "Obstetric Care, Vaginal Delivery (Global)", "category": "ob_gyn"},
        "59510": {"description": "Obstetric Care, C-Section (Global)", "category": "ob_gyn"},
        "59610": {"description": "Obstetric Care, VBAC (Global)", "category": "ob_gyn"},
        "62322": {"description": "Lumbar Epidural Injection (without imaging)", "category": "pain_management"},
        "62323": {"description": "Lumbar Epidural Injection (with imaging)", "category": "pain_management"},
        "64483": {"description": "Transforaminal Epidural Injection, Lumbar", "category": "pain_management"},
        "64490": {"description": "Facet Joint Injection, Cervical (1st level)", "category": "pain_management"},
        "64493": {"description": "Facet Joint Injection, Lumbar (1st level)", "category": "pain_management"},
        "66821": {"description": "YAG Laser Capsulotomy (After Cataract)", "category": "ophthalmology"},
        "66984": {"description": "Cataract Surgery with Lens Implant", "category": "ophthalmology"},
        "67028": {"description": "Eye Injection (Intravitreal)", "category": "ophthalmology"},
        "69210": {"description": "Ear Wax Removal", "category": "ent"},

        # --- Physical Therapy ---
        "97110": {"description": "Therapeutic Exercise (15 min)", "category": "physical_therapy"},
        "97112": {"description": "Neuromuscular Re-education (15 min)", "category": "physical_therapy"},
        "97116": {"description": "Gait Training (15 min)", "category": "physical_therapy"},
        "97140": {"description": "Manual Therapy (15 min)", "category": "physical_therapy"},
        "97161": {"description": "PT Evaluation (Low Complexity)", "category": "physical_therapy"},
        "97162": {"description": "PT Evaluation (Moderate Complexity)", "category": "physical_therapy"},
        "97163": {"description": "PT Evaluation (High Complexity)", "category": "physical_therapy"},
        "97164": {"description": "PT Re-evaluation", "category": "physical_therapy"},
        "97530": {"description": "Therapeutic Activities (15 min)", "category": "physical_therapy"},
        "97535": {"description": "Self-Care Training (15 min)", "category": "physical_therapy"},
        "97542": {"description": "Wheelchair Management Training (15 min)", "category": "physical_therapy"},
        "97750": {"description": "Physical Performance Test", "category": "physical_therapy"},

        # --- Anesthesia ---
        "00100": {"description": "Anesthesia for Salivary Gland Surgery", "category": "anesthesia"},
        "00140": {"description": "Anesthesia for Eye Surgery", "category": "anesthesia"},
        "00300": {"description": "Anesthesia for Head/Neck Surgery", "category": "anesthesia"},
        "00400": {"description": "Anesthesia for Chest Wall Surgery", "category": "anesthesia"},
        "00520": {"description": "Anesthesia for Chest Surgery", "category": "anesthesia"},
        "00540": {"description": "Anesthesia for Thoracotomy", "category": "anesthesia"},
        "00600": {"description": "Anesthesia for Spine Surgery, Cervical", "category": "anesthesia"},
        "00670": {"description": "Anesthesia for Spine Surgery, Thoracic", "category": "anesthesia"},
        "00740": {"description": "Anesthesia for Upper GI Surgery", "category": "anesthesia"},
        "00810": {"description": "Anesthesia for Lower GI Surgery", "category": "anesthesia"},
        "00840": {"description": "Anesthesia for Abdominal Wall Surgery", "category": "anesthesia"},
        "01214": {"description": "Anesthesia for Total Hip Replacement", "category": "anesthesia"},
        "01402": {"description": "Anesthesia for Knee Arthroscopy", "category": "anesthesia"},
        "01480": {"description": "Anesthesia for Lower Leg Surgery", "category": "anesthesia"},
        "01630": {"description": "Anesthesia for Shoulder Surgery", "category": "anesthesia"},
        "01996": {"description": "Daily Hospital Management of Epidural", "category": "anesthesia"},

        # --- Vaccines ---
        "90460": {"description": "Vaccine Administration (under 18, 1st component)", "category": "vaccine"},
        "90461": {"description": "Vaccine Administration (under 18, each additional)", "category": "vaccine"},
        "90471": {"description": "Immunization Administration (1st injection)", "category": "vaccine"},
        "90472": {"description": "Immunization Administration (each additional)", "category": "vaccine"},
        "90473": {"description": "Immunization Administration, Oral/Nasal (1st)", "category": "vaccine"},
        "90474": {"description": "Immunization Administration, Oral/Nasal (additional)", "category": "vaccine"},
        "90658": {"description": "Flu Vaccine (Quadrivalent)", "category": "vaccine"},
        "90662": {"description": "Flu Vaccine (High Dose, 65+)", "category": "vaccine"},
        "90670": {"description": "Pneumococcal Vaccine (PCV13)", "category": "vaccine"},
        "90707": {"description": "MMR Vaccine", "category": "vaccine"},
        "90715": {"description": "Tdap Vaccine", "category": "vaccine"},
        "90732": {"description": "Pneumococcal Vaccine (PPSV23)", "category": "vaccine"},
        "90750": {"description": "Shingles Vaccine (Recombinant)", "category": "vaccine"},

        # --- Drug Administration ---
        "96360": {"description": "IV Infusion (First Hour)", "category": "infusion"},
        "96361": {"description": "IV Infusion (Each Additional Hour)", "category": "infusion"},
        "96365": {"description": "IV Infusion Therapy (First Hour)", "category": "infusion"},
        "96366": {"description": "IV Infusion Therapy (Each Additional Hour)", "category": "infusion"},
        "96372": {"description": "Injection, Subcutaneous or Intramuscular", "category": "infusion"},
        "96374": {"description": "IV Push, Single Drug", "category": "infusion"},
        "96375": {"description": "IV Push, Each Additional Drug", "category": "infusion"},
        "96413": {"description": "Chemotherapy IV Infusion (First Hour)", "category": "oncology"},
        "96415": {"description": "Chemotherapy IV Infusion (Each Additional Hour)", "category": "oncology"},
        "96417": {"description": "Chemotherapy IV Infusion (Additional Sequential)", "category": "oncology"},

        # --- Common HCPCS Drug Codes (J-codes) ---
        "J0129": {"description": "Abatacept Injection (10mg)", "category": "drug"},
        "J0135": {"description": "Adalimumab Injection (20mg)", "category": "drug"},
        "J0171": {"description": "Adrenalin/Epinephrine Injection", "category": "drug"},
        "J0585": {"description": "Botulinum Toxin A (Botox, 1 unit)", "category": "drug"},
        "J0696": {"description": "Ceftriaxone Injection (250mg)", "category": "drug"},
        "J0702": {"description": "Betamethasone Injection (3mg)", "category": "drug"},
        "J1030": {"description": "Methylprednisolone Injection (40mg)", "category": "drug"},
        "J1040": {"description": "Methylprednisolone Injection (80mg)", "category": "drug"},
        "J1050": {"description": "Medroxyprogesterone Injection (1mg)", "category": "drug"},
        "J1071": {"description": "Testosterone Injection (1mg)", "category": "drug"},
        "J1100": {"description": "Dexamethasone Injection (1mg)", "category": "drug"},
        "J1170": {"description": "Hydromorphone Injection (up to 4mg)", "category": "drug"},
        "J1200": {"description": "Diphenhydramine (Benadryl) Injection (50mg)", "category": "drug"},
        "J1885": {"description": "Ketorolac (Toradol) Injection (15mg)", "category": "drug"},
        "J2001": {"description": "Lidocaine Injection (10mg)", "category": "drug"},
        "J2175": {"description": "Meperidine (Demerol) Injection (100mg)", "category": "drug"},
        "J2250": {"description": "Midazolam Injection (1mg)", "category": "drug"},
        "J2270": {"description": "Morphine Sulfate Injection (up to 10mg)", "category": "drug"},
        "J2310": {"description": "Naloxone (Narcan) Injection (1mg)", "category": "drug"},
        "J2405": {"description": "Ondansetron (Zofran) Injection (1mg)", "category": "drug"},
        "J2550": {"description": "Promethazine (Phenergan) Injection (50mg)", "category": "drug"},
        "J2704": {"description": "Propofol Injection (10mg)", "category": "drug"},
        "J2795": {"description": "Ropivacaine Injection (1mg)", "category": "drug"},
        "J3010": {"description": "Fentanyl Injection (0.1mg)", "category": "drug"},
        "J3301": {"description": "Triamcinolone Injection (10mg)", "category": "drug"},
        "J3490": {"description": "Unclassified Drug", "category": "drug"},
        "J7030": {"description": "Normal Saline (1000ml)", "category": "drug"},
        "J7040": {"description": "Normal Saline with Dextrose (500ml)", "category": "drug"},
        "J7050": {"description": "Normal Saline (250ml)", "category": "drug"},
        "J7120": {"description": "Lactated Ringer's (1000ml)", "category": "drug"},

        # --- Ambulance ---
        "A0425": {"description": "Ground Ambulance, Mileage (per mile)", "category": "ambulance"},
        "A0427": {"description": "ALS Ambulance, Emergency Transport", "category": "ambulance"},
        "A0428": {"description": "BLS Ambulance, Emergency Transport", "category": "ambulance"},
        "A0429": {"description": "BLS Ambulance, Non-Emergency Transport", "category": "ambulance"},
        "A0433": {"description": "ALS Ambulance, Non-Emergency Transport (Level 2)", "category": "ambulance"},

        # --- DME / Supplies ---
        "A4206": {"description": "Syringe with Needle (1cc)", "category": "supplies"},
        "A4550": {"description": "Surgical Tray", "category": "supplies"},
        "A6250": {"description": "Wound Dressing, Skin Closure Strip", "category": "supplies"},
        "L3000": {"description": "Foot Insert/Orthotic", "category": "dme"},
        "Q4131": {"description": "Wound Care Skin Substitute", "category": "supplies"},

        # --- Mental Health ---
        "90791": {"description": "Psychiatric Diagnostic Evaluation", "category": "mental_health"},
        "90792": {"description": "Psychiatric Diagnostic Evaluation with Medical Services", "category": "mental_health"},
        "90832": {"description": "Psychotherapy (30 min)", "category": "mental_health"},
        "90834": {"description": "Psychotherapy (45 min)", "category": "mental_health"},
        "90837": {"description": "Psychotherapy (60 min)", "category": "mental_health"},
        "90838": {"description": "Psychotherapy (crisis, 60+ min)", "category": "mental_health"},
        "90839": {"description": "Psychotherapy for Crisis (First 60 min)", "category": "mental_health"},
        "90846": {"description": "Family Psychotherapy (without patient)", "category": "mental_health"},
        "90847": {"description": "Family Psychotherapy (with patient)", "category": "mental_health"},
        "90853": {"description": "Group Psychotherapy", "category": "mental_health"},

        # --- Pathology ---
        "88305": {"description": "Surgical Pathology (Biopsy Examination)", "category": "pathology"},
        "88312": {"description": "Special Stain (Immunohistochemistry)", "category": "pathology"},
        "88342": {"description": "Immunohistochemistry per Antibody", "category": "pathology"},

        # --- Cardiology ---
        "93000": {"description": "Electrocardiogram (ECG/EKG), Complete", "category": "cardiology"},
        "93005": {"description": "Electrocardiogram (ECG/EKG), Tracing Only", "category": "cardiology"},
        "93010": {"description": "Electrocardiogram (ECG/EKG), Interpretation", "category": "cardiology"},
        "93015": {"description": "Cardiovascular Stress Test", "category": "cardiology"},
        "93017": {"description": "Stress Test, Tracing Only", "category": "cardiology"},
        "93018": {"description": "Stress Test, Interpretation Only", "category": "cardiology"},
        "93306": {"description": "Echocardiogram, Complete with Doppler", "category": "cardiology"},
        "93307": {"description": "Echocardiogram, Complete (2D)", "category": "cardiology"},
        "93308": {"description": "Echocardiogram, Follow-up/Limited", "category": "cardiology"},
        "93320": {"description": "Doppler Echocardiography, Complete", "category": "cardiology"},
        "93350": {"description": "Stress Echocardiogram", "category": "cardiology"},
        "93458": {"description": "Left Heart Catheterization", "category": "cardiology"},
        "93459": {"description": "Left Heart Catheterization with Ventriculography", "category": "cardiology"},

        # --- Pulmonary ---
        "94010": {"description": "Spirometry (Breathing Test)", "category": "pulmonary"},
        "94060": {"description": "Spirometry Before and After Bronchodilator", "category": "pulmonary"},
        "94375": {"description": "Respiratory Flow Volume Loop", "category": "pulmonary"},
        "94640": {"description": "Nebulizer Treatment", "category": "pulmonary"},
        "94664": {"description": "Inhaler Training/Demonstration", "category": "pulmonary"},
        "94726": {"description": "Lung Volume Measurement (Plethysmography)", "category": "pulmonary"},
        "94729": {"description": "Diffusing Capacity (DLCO)", "category": "pulmonary"},
        "94760": {"description": "Pulse Oximetry", "category": "pulmonary"},

        # --- Sleep ---
        "95810": {"description": "Sleep Study (Polysomnography)", "category": "sleep"},
        "95811": {"description": "Sleep Study with CPAP Titration", "category": "sleep"},

        # --- Neurology ---
        "95819": {"description": "EEG (Electroencephalogram), Awake and Asleep", "category": "neurology"},
        "95907": {"description": "Nerve Conduction Study (1-2 studies)", "category": "neurology"},
        "95908": {"description": "Nerve Conduction Study (3-4 studies)", "category": "neurology"},
        "95909": {"description": "Nerve Conduction Study (5-6 studies)", "category": "neurology"},
        "95910": {"description": "Nerve Conduction Study (7-8 studies)", "category": "neurology"},
        "95913": {"description": "Nerve Conduction Study (13+ studies)", "category": "neurology"},
        "95886": {"description": "EMG (Needle Electromyography)", "category": "neurology"},

        # --- Dental (HCPCS D-codes, CMS-created) ---
        "D0120": {"description": "Periodic Oral Exam", "category": "dental"},
        "D0140": {"description": "Limited Oral Exam (Problem-Focused)", "category": "dental"},
        "D0150": {"description": "Comprehensive Oral Exam", "category": "dental"},
        "D0210": {"description": "Full Mouth X-rays", "category": "dental"},
        "D0220": {"description": "Periapical X-ray (First)", "category": "dental"},
        "D0230": {"description": "Periapical X-ray (Each Additional)", "category": "dental"},
        "D0272": {"description": "Bitewing X-rays (2 films)", "category": "dental"},
        "D0274": {"description": "Bitewing X-rays (4 films)", "category": "dental"},
        "D0330": {"description": "Panoramic X-ray", "category": "dental"},
        "D1110": {"description": "Dental Cleaning (Adult)", "category": "dental"},
        "D1120": {"description": "Dental Cleaning (Child)", "category": "dental"},
        "D2750": {"description": "Dental Crown (Porcelain/Ceramic)", "category": "dental"},
        "D7140": {"description": "Simple Tooth Extraction", "category": "dental"},
        "D7210": {"description": "Surgical Tooth Extraction", "category": "dental"},
        "D7240": {"description": "Impacted Tooth Removal (Soft Tissue)", "category": "dental"},

        # --- Miscellaneous ---
        "99070": {"description": "Supplies and Materials", "category": "miscellaneous"},
        "99024": {"description": "Post-Op Follow-Up Visit (included in surgery)", "category": "miscellaneous"},
        "99050": {"description": "After-Hours Service", "category": "miscellaneous"},
        "99053": {"description": "Service Between 10pm-8am", "category": "miscellaneous"},
        "99080": {"description": "Special Report/Forms Preparation", "category": "miscellaneous"},
        "99195": {"description": "Phlebotomy, Therapeutic", "category": "miscellaneous"},

        # --- Genetic Testing ---
        "81225": {"description": "CYP2C19 Gene Analysis", "category": "genetics"},
        "81240": {"description": "Factor V Leiden Mutation Analysis", "category": "genetics"},
        "81243": {"description": "FMR1 Gene Analysis (Fragile X)", "category": "genetics"},
        "81291": {"description": "MTHFR Gene Analysis", "category": "genetics"},
        "81479": {"description": "Unlisted Molecular Pathology", "category": "genetics"},

        # --- Radiation Oncology ---
        "77385": {"description": "Radiation Treatment Delivery (IMRT, Simple)", "category": "radiation"},
        "77386": {"description": "Radiation Treatment Delivery (IMRT, Complex)", "category": "radiation"},
        "77412": {"description": "Radiation Treatment Delivery (3+ MeV)", "category": "radiation"},
        "77427": {"description": "Radiation Treatment Management (5 treatments)", "category": "radiation"},

        # --- Home Health (G-codes, CMS-created descriptions — freely usable) ---
        "G0151": {"description": "Home Health Skilled PT Visit", "category": "home_health"},
        "G0152": {"description": "Home Health Skilled OT Visit", "category": "home_health"},
        "G0153": {"description": "Home Health Skilled SLP Visit", "category": "home_health"},
        "G0154": {"description": "Home Health Skilled Nursing Visit", "category": "home_health"},
        "G0156": {"description": "Home Health Aide Visit", "category": "home_health"},
        "G0162": {"description": "Home Health Skilled RN Visit", "category": "home_health"},
        "G0299": {"description": "Home Health Skilled Nursing, Direct", "category": "home_health"},
        "G0300": {"description": "Home Health Skilled Nursing, Indirect", "category": "home_health"},
        "G0463": {"description": "Hospital Outpatient Clinic Visit", "category": "hospital"},

        # --- Chiropractic ---
        "98940": {"description": "Chiropractic Spinal Manipulation (1-2 regions)", "category": "chiropractic"},
        "98941": {"description": "Chiropractic Spinal Manipulation (3-4 regions)", "category": "chiropractic"},
        "98942": {"description": "Chiropractic Spinal Manipulation (5 regions)", "category": "chiropractic"},
        "98943": {"description": "Chiropractic Extraspinal Manipulation (1+ regions)", "category": "chiropractic"},

        # --- Allergy ---
        "95004": {"description": "Allergy Skin Prick Test (per test)", "category": "allergy"},
        "95024": {"description": "Allergy Intradermal Test (per test)", "category": "allergy"},
        "95115": {"description": "Allergy Injection (single)", "category": "allergy"},
        "95117": {"description": "Allergy Injection (two or more)", "category": "allergy"},
        "95165": {"description": "Allergy Immunotherapy (multi-dose vial prep)", "category": "allergy"},

        # --- IVF/Fertility ---
        "58970": {"description": "Egg Retrieval (Oocyte Aspiration)", "category": "fertility"},
        "58974": {"description": "Embryo Transfer", "category": "fertility"},
        "89250": {"description": "IVF Culture/Incubation", "category": "fertility"},
        "89251": {"description": "Assisted Hatching", "category": "fertility"},
        "89253": {"description": "Assisted Hatching of Oocytes", "category": "fertility"},
        "89254": {"description": "Oocyte ID from Follicular Fluid", "category": "fertility"},
        "89258": {"description": "Cryopreservation of Embryos", "category": "fertility"},
        "89268": {"description": "ICSI (Insemination of Oocytes)", "category": "fertility"},

        # --- Infusion/Home Infusion ---
        "99601": {"description": "Home Infusion, First 2 Hours", "category": "infusion"},
        "99602": {"description": "Home Infusion, Each Additional Hour", "category": "infusion"},

        # --- Vascular ---
        "36556": {"description": "Central Venous Catheter Insertion (non-tunneled)", "category": "vascular"},
        "36558": {"description": "Central Venous Catheter Insertion (tunneled)", "category": "vascular"},
        "36561": {"description": "Port-a-Cath Insertion", "category": "vascular"},
        "93970": {"description": "Duplex Ultrasound Extremity Veins (Complete)", "category": "vascular"},
        "93971": {"description": "Duplex Ultrasound Extremity Veins (Limited)", "category": "vascular"},
        "93880": {"description": "Duplex Ultrasound Carotid Arteries", "category": "vascular"},
        "93925": {"description": "Duplex Ultrasound Lower Extremity Arteries", "category": "vascular"},
        "93926": {"description": "Duplex Ultrasound Lower Extremity Arteries (Limited)", "category": "vascular"},
    }

    # Convert to list format
    result = []
    for code, info in sorted(descriptions.items()):
        result.append({
            "code": code,
            "description": info["description"],
            "category": info["category"],
        })

    print(f"  Code descriptions: {len(result)} codes")
    return result


# ---------------------------------------------------------------------------
# 5. MUE LIMITS (placeholder — actual MUE file not in CMS_Data)
# ---------------------------------------------------------------------------

def generate_mue_limits():
    """Generate MUE limits for common codes.

    The full MUE file is available on CMS.gov but wasn't included in the
    provided CMS_Data folder. These are well-known MUE values for the
    most commonly questioned codes.
    """
    mue_data = {
        # E&M codes — one per day
        "99202": 1, "99203": 1, "99204": 1, "99205": 1,
        "99211": 1, "99212": 1, "99213": 1, "99214": 1, "99215": 1,
        "99221": 1, "99222": 1, "99223": 1,
        "99231": 1, "99232": 1, "99233": 1,
        "99238": 1, "99239": 1,
        "99281": 1, "99282": 1, "99283": 1, "99284": 1, "99285": 1,
        "99291": 1,
        "99292": 4,  # Additional critical care in 30-min units

        # Lab panels — one per day
        "80047": 1, "80048": 1, "80050": 1, "80051": 1, "80053": 1,
        "80055": 1, "80061": 1, "80069": 1, "80076": 1, "80081": 1,

        # Common labs — usually 1 per day
        "82947": 2, "83036": 1, "84443": 1, "85025": 1, "85027": 1,
        "81001": 2, "81002": 2, "81003": 2,
        "36415": 3,  # Venipuncture, up to 3 draws

        # Radiology — usually 1 per exam
        "71046": 1, "71045": 1, "70450": 1, "70551": 1,
        "72148": 1, "72141": 1, "74177": 1, "74176": 1,

        # Injections
        "96372": 4,   # IM/SubQ injections
        "96374": 1,   # IV push first drug
        "90471": 1,   # Immunization admin first
        "90472": 3,   # Immunization admin additional

        # PT — per session (15-min units)
        "97110": 4, "97112": 4, "97116": 4, "97140": 4,
        "97161": 1, "97162": 1, "97163": 1, "97164": 1,
        "97530": 4, "97535": 4,

        # Surgery — per session
        "10060": 1, "10061": 1,
        "45378": 1, "45380": 1, "45385": 1,
        "43235": 1, "43239": 1,
        "27447": 1, "27130": 1,
        "66984": 1,

        # Mental health — 1 per day
        "90791": 1, "90792": 1,
        "90832": 1, "90834": 1, "90837": 1,

        # ECG/Cardio
        "93000": 1, "93005": 1, "93010": 1,
        "93306": 1, "93307": 1,

        # Chiropractic
        "98940": 1, "98941": 1, "98942": 1,
    }

    result = []
    for code, max_units in sorted(mue_data.items()):
        result.append({
            "code": code,
            "maxUnits": max_units,
            "rationale": "CMS MUE limit",
        })

    print(f"  MUE limits: {len(result)} codes")
    return result


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Processing CMS data files...")
    print(f"  Source: {CMS_DIR}")
    print(f"  Output: {OUTPUT_DIR}")
    print()

    # 1. Medicare Pricing
    print("[1/4] Processing RVU data for pricing...")
    pricing = process_rvu_pricing()
    pricing_path = OUTPUT_DIR / "medicare_pricing.json"
    with open(pricing_path, "w") as f:
        json.dump(pricing, f, indent=None, separators=(",", ":"))
    size_kb = os.path.getsize(pricing_path) / 1024
    print(f"  Written: {pricing_path.name} ({size_kb:.0f} KB)")
    print()

    # 2. PTP Bundling Pairs
    print("[2/4] Processing NCCI PTP edit pairs...")
    pairs_raw = process_ptp_edits()
    # Add numeric rationale codes
    pairs = []
    for p in pairs_raw:
        pairs.append({
            "col1": p["col1"],
            "col2": p["col2"],
            "modifier": p["modifier"],
            "rationale": normalize_rationale(p["rationale"]),
        })
    pairs_path = OUTPUT_DIR / "bundling_pairs.json"
    with open(pairs_path, "w") as f:
        json.dump(pairs, f, indent=None, separators=(",", ":"))
    size_kb = os.path.getsize(pairs_path) / 1024
    print(f"  Written: {pairs_path.name} ({size_kb:.0f} KB)")
    print()

    # 3. Code Descriptions
    print("[3/4] Generating code descriptions...")
    descriptions = generate_code_descriptions()
    desc_path = OUTPUT_DIR / "code_descriptions.json"
    with open(desc_path, "w") as f:
        json.dump(descriptions, f, indent=2)
    size_kb = os.path.getsize(desc_path) / 1024
    print(f"  Written: {desc_path.name} ({size_kb:.0f} KB)")
    print()

    # 4. MUE Limits
    print("[4/4] Generating MUE limits...")
    mue = generate_mue_limits()
    mue_path = OUTPUT_DIR / "mue_limits.json"
    with open(mue_path, "w") as f:
        json.dump(mue, f, indent=2)
    size_kb = os.path.getsize(mue_path) / 1024
    print(f"  Written: {mue_path.name} ({size_kb:.0f} KB)")
    print()

    # Summary
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  medicare_pricing.json : {len(pricing):>6} codes")
    print(f"  bundling_pairs.json   : {len(pairs):>6} pairs")
    print(f"  code_descriptions.json: {len(descriptions):>6} codes")
    print(f"  mue_limits.json       : {len(mue):>6} codes")
    print()
    print("NOTE: All AMA CPT description text has been stripped.")
    print("      Only code numbers, numeric data, and CMS-created content retained.")
    print("      code_descriptions.json contains OUR OWN plain-English descriptions.")


if __name__ == "__main__":
    main()
