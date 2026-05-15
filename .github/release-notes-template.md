# {{VERSION}}

[{{VERSION}}](https://github.com/{{REPO}}/tree/{{VERSION}}) · [`{{COMMIT_SHORT}}`](https://github.com/{{REPO}}/commit/{{COMMIT_FULL}})

{{CHANGELOG}}

---

## Release Info

| Field | Value |
| --- | --- |
| Version | `{{VERSION}}` |
| Commit | `{{COMMIT_SHORT}}` |
| Branch | `{{BRANCH}}` |
| Build Date | {{BUILD_DATE_UTC}} |
| Python Version | {{PYTHON_VERSION}} |

## Checksums (SHA256)

```
{{CHECKSUMS}}
```

## Install

### Quick install (Windows PowerShell)

```powershell
irm https://github.com/{{REPO}}/releases/download/{{VERSION}}/install.ps1 | iex
```

### Quick install (Linux / macOS)

```bash
curl -fsSL https://github.com/{{REPO}}/releases/download/{{VERSION}}/install.sh | bash
```

### Install specific version (generic installer)

```powershell
irm https://raw.githubusercontent.com/{{REPO}}/main/install.ps1 | iex
# Or pin this version:
& { $env:JPG2PDF_VERSION = "{{VERSION}}"; irm https://raw.githubusercontent.com/{{REPO}}/main/install.ps1 | iex }
```

```bash
curl -fsSL https://raw.githubusercontent.com/{{REPO}}/main/install.sh | bash
# Or pin this version:
curl -fsSL https://raw.githubusercontent.com/{{REPO}}/main/install.sh | bash -s -- --version {{VERSION}}
```

### Manual download

Download the appropriate archive for your platform from the assets below, extract, and place the binary in your PATH.

## Assets

| Platform | Architecture | File |
| --- | --- | --- |
| Windows | amd64 | `jpg2pdf-windows-x64.exe` |
| Linux   | amd64 | `jpg2pdf-linux-x64` |
| Linux   | arm64 | `jpg2pdf-linux-arm64` |
| macOS   | amd64 | `jpg2pdf-macos-x64` |
| macOS   | arm64 | `jpg2pdf-macos-arm64` |
