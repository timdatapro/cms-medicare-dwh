"""
CMS Synthetic Medicare Claims DWH
Script  : load_icd10cm.py
Purpose : Extract ICD-10-CM codes from simple-icd-10-cm package and write to CSV
          for loading into mart.dim_diagnosis via PostgreSQL \COPY
Output  : icd10cm.csv (place in C:/Temp/cms_medicare/ before running 14_mart_dim_diagnosis.sql)

Requirements:
    pip install simple-icd-10-cm

Notes:
    - The library contains 39 duplicate codes (B10, B20, B99, C50, C7A, etc.)
      Deduplication via seen set is required to avoid primary key violation on load.
    - Output: 98,466 unique rows covering 94.3% of codes found in Synthea claims.
    - Remaining 22 Synthea-specific codes (ICD-10-PCS codes, suffix-less variants)
      are added manually via INSERT in 14_mart_dim_diagnosis.sql.
"""

import simple_icd_10_cm as cm
import csv
import sys

OUTPUT_FILE = "icd10cm.csv"

def main():
    print("Extracting ICD-10-CM codes...")
    all_codes = cm.get_all_codes(with_dots=False)

    seen = set()
    rows = []
    skipped = 0

    for code in all_codes:
        if code in seen:
            skipped += 1
            continue
        seen.add(code)

        try:
            desc        = cm.get_description(code)
            ancestors   = cm.get_ancestors(code)
            is_leaf     = cm.is_leaf(code)

            # Hierarchy: ancestors ordered from nearest to furthest
            chapter_num  = ancestors[-1] if ancestors else ""
            chapter_desc = cm.get_description(chapter_num) if chapter_num else ""
            block        = ancestors[1]  if len(ancestors) > 1 else ""
            block_desc   = cm.get_description(block) if block else ""
            parent       = ancestors[0]  if ancestors else ""
            parent_desc  = cm.get_description(parent) if parent else ""

            rows.append({
                "icd_dgns_cd":  code,
                "description":  desc,
                "is_billable":  is_leaf,
                "chapter_num":  chapter_num,
                "chapter_desc": chapter_desc,
                "block_code":   block,
                "block_desc":   block_desc,
                "parent_code":  parent,
                "parent_desc":  parent_desc,
            })
        except Exception as e:
            print(f"  WARNING: skipped {code} — {e}", file=sys.stderr)

    print(f"Total codes processed : {len(all_codes)}")
    print(f"Duplicates skipped    : {skipped}")
    print(f"Unique rows to write  : {len(rows)}")

    fieldnames = [
        "icd_dgns_cd", "description", "is_billable",
        "chapter_num", "chapter_desc",
        "block_code",  "block_desc",
        "parent_code", "parent_desc",
    ]

    with open(OUTPUT_FILE, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Output written to: {OUTPUT_FILE}")
    print("Next step: run 14_mart_dim_diagnosis.sql in DBeaver to load into mart.dim_diagnosis")


if __name__ == "__main__":
    main()
