"""Check placeholder contracts across every maintained catalog and configured language."""

import json

from catalog_placeholder_matrix import ROOT, WORK, audit_documents
from matrix_classification import summarize_report


def main():
    report = audit_documents(WORK['load_catalogs'](ROOT, None))
    report['diagnostics'] = summarize_report(report)
    output = ROOT / 'datasources/imports/translation-matrix/catalog-placeholders.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"Catalog placeholders: {report['counts']}; report: {output}", flush=True)
    return int(bool(report['failures']))


if __name__ == '__main__':
    raise SystemExit(main())
