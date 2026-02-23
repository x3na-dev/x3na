# Security Policy

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please report it responsibly.

### How to Report

**DO NOT** open a public GitHub issue for security vulnerabilities.

Please send a detailed report to:

- Email: security@x3na.io (replace with your actual contact)
- Or use GitHub's private vulnerability reporting feature

### What to Include

1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 7 days
- **Resolution**: Depends on severity

### Scope

The following are in scope:

- Smart contracts in `/contracts/`
- Any issues that could lead to loss of funds
- Access control bypasses
- Reentrancy vulnerabilities

### Out of Scope

- Frontend/UI issues
- Third-party dependencies (report to respective maintainers)
- Issues in test files

## Security Measures

### Contract Security

- **Upgradeable Proxies**: Using OpenZeppelin's TransparentUpgradeableProxy
- **Access Control**: Role-based permissions with `AccessControlUpgradeable`
- **Reentrancy Protection**: All external calls protected with `ReentrancyGuardUpgradeable`
- **Pausable**: Emergency pause functionality available

### Known Considerations

- Admin keys can upgrade contracts (standard for upgradeable patterns)
- Operator role can manage rounds

## Audit Status

- [ ] Formal audit pending

---

Thank you for helping keep X3NA secure!
