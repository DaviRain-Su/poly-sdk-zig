# ROADMAP - Source of Truth

This is the single source of truth for project planning. All work derives from here.

## Current Status

**Version**: v0.0.0 (Pre-release)  
**Phase**: v0.1 - Core Foundation

---

## v0.1 - Core Foundation

> **Goal**: Basic types, HTTP client, and read-only public API.
> **Deliverable**: Query market data without authentication.

```zig
var client = try poly.Client.init(allocator, .{});
const markets = try client.markets(.{});
```

### Stories

| Story | Status | Depends On |
|-------|--------|------------|
| [v0.1-types](./stories/v0.1-types.md) | 🔨 In Progress | - |
| [v0.1-error](./stories/v0.1-error.md) | ⏳ Pending | - |
| [v0.1-http](./stories/v0.1-http.md) | ⏳ Pending | v0.1-error |
| [v0.1-public-api](./stories/v0.1-public-api.md) | ⏳ Pending | v0.1-http, v0.1-types |

### Progress

- [x] Project setup (build.zig, structure)
- [x] Decimal type implemented
- [ ] Address, UUID, Secret types
- [ ] Error types
- [ ] HTTP client
- [ ] Public API endpoints

---

## v0.2 - Authentication & Orders

> **Goal**: Full authentication and order management.
> **Deliverable**: Place and manage orders.

```zig
var auth = try client.authenticate(&signer);
try auth.postOrder(order);
```

### Stories (Planned)

| Story | Status | Description |
|-------|--------|-------------|
| v0.2-crypto | ⏳ Pending | secp256k1, keccak256, HMAC |
| v0.2-l1-auth | ⏳ Pending | EIP-712 signing |
| v0.2-l2-auth | ⏳ Pending | HMAC request signing |
| v0.2-orders | ⏳ Pending | Order builder, post/cancel |

---

## v0.3 - Builder & Extras

> **Goal**: Builder program and additional features.

---

## v0.4 - WebSocket

> **Goal**: Real-time data subscriptions.

---

## v1.0 - Stable Release

> **Goal**: Production-ready, fully tested.

---

## Status Legend

| Icon | Meaning |
|------|---------|
| ⏳ | Pending |
| 🔨 | In Progress |
| ✅ | Complete |
| ❌ | Blocked |

---

## Changelog

| Date | Change |
|------|--------|
| 2024-12-31 | Initial ROADMAP, v0.1 stories created |
