# Changelog

## 1.0.2

- Added automatic commit of successful processing results to `main`.
- Workflow now requests `contents: write` only to publish generated result files.
- Results continue to be uploaded as GitHub Actions artifacts.


## 1.0.1

- Added `SETUP.cmd` for systems using restrictive PowerShell execution policies.
- Added `RUN.cmd` for a convenient local launch.
- Added GitHub Actions workflow at `.github/workflows/translate.yml` for remote execution.
- Added manual workflow inputs for `input.wiki`, Wikipedia title, or Wikipedia URL.
- Added secure `GEMINI_API_KEY` secret integration.
- Added GitHub Actions caching and result artifacts.
