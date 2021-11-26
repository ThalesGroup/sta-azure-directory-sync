Describe here all the security policies in place on this repository to help your contributors to handle security issues efficiently.

## Goods practices to follow

:warning:**You must never store credentials information into source code or config file in a GitHub repository** 
- Block sensitive data being pushed to GitHub by git-secrets or its likes as a git pre-commit hook
- Audit for slipped secrets with dedicated tools
- Use environment variables for secrets in CI/CD (e.g. GitHub Secrets) and secret managers in production

# Security Policy

## Supported Versions
Only the latest code available in this repository is supported

| Version | Supported          |
| ------- | ------------------ |
| 1.0.0   | :white_check_mark: |

## Reporting a Vulnerability

For any vulnerability found in the code, please contact the support team by opening a new ticket on the Thales Support Portal
https://supportportal.thalesgroup.com/