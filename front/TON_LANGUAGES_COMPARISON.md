# TON Smart Contract Languages Comparison: Tolk vs FunC vs Fift

## Overview

This document compares the three main languages used for developing smart contracts on The Open Network (TON) blockchain.

---

## Tolk vs FunC vs Fift

### **Tolk** 🆕 (2025)
- **Type**: Modern high-level smart contract language
- **Status**: New language designed to replace FunC
- **Syntax**: Inspired by TypeScript, Rust, and Kotlin
- **Primary Use**: Smart contract development

### **FunC** (Functional C)
- **Type**: High-level smart contract language
- **Status**: Original and established language for TON
- **Syntax**: Resembles C programming language
- **Primary Use**: Smart contract development

### **Fift**
- **Type**: Low-level scripting language
- **Status**: Assembly-level language for TON
- **Syntax**: Stack-based, assembly-like
- **Primary Use**: Low-level operations, testing, and contract deployment

---

## Detailed Comparison: Tolk vs FunC

### 1. **Syntax & Language Design**

| Feature | Tolk | FunC |
|---------|------|------|
| **Syntax Style** | Modern, TypeScript/Rust/Kotlin-inspired | C-like, functional |
| **Readability** | High - expressive and intuitive | Moderate - C-style syntax |
| **Learning Curve** | Easier for modern developers | Familiar to C developers |

**Example:**

**FunC:**
```func
(int, slice, int, int) get_data() method_id {
    return (123, begin_cell().store_uint(456, 16).end_cell().begin_parse(), 789, 101);
}
```

**Tolk:**
```tolk
struct Data {
    int value1;
    slice value2;
    int value3;
    int value4;
}

method get_data() -> Data {
    return Data{
        value1: 123,
        value2: begin_cell().store_uint(456, 16).end_cell().begin_parse(),
        value3: 789,
        value4: 101
    };
}
```

---

### 2. **Type System**

| Feature | Tolk | FunC |
|---------|------|------|
| **Structures** | ✅ Native support for structures | ❌ No structures (uses unnamed tuples) |
| **Type Safety** | Strong, modern type system | Basic type checking |
| **Data Organization** | Clear, named fields | Long unnamed tuples: `(int, slice, int, int)` |

**FunC Problem:**
```func
# Hard to understand what each element represents
(int balance, slice owner_address, int last_payment, int total_payments) = get_user_data();
```

**Tolk Solution:**
```tolk
struct UserData {
    int balance;
    slice owner_address;
    int last_payment;
    int total_payments;
}

UserData data = get_user_data();
// Much clearer: data.balance, data.owner_address, etc.
```

---

### 3. **Method Calls & Mutability**

| Feature | Tolk | FunC |
|---------|------|------|
| **Syntax** | Dot notation: `cell.store_uint()` | Function calls: `store_uint(cell, value)` |
| **Mutability Indicator** | No special notation needed | Uses tilde (`~`) for mutating functions |
| **Style** | JavaScript-like | Functional programming style |

**FunC:**
```func
cell ~store_uint(amount, 64);  # ~ indicates mutation
slice data = cell.begin_parse();
```

**Tolk:**
```tolk
cell.store_uint(amount, 64);  # No tilde needed
slice data = cell.begin_parse();
```

---

### 4. **Standard Library**

| Feature | Tolk | FunC |
|---------|------|------|
| **Organization** | Split into multiple files (`common.tolk`, `tvm-dicts.tolk`) | Single `stdlib.fc` file |
| **Auto-imports** | `common.tolk` always available | All functions in stdlib |
| **Method Style** | Many functions converted to object methods | Global functions |
| **Low-level Access** | Abstracts TVM instructions | Direct TVM instruction mapping |

**FunC:**
```func
#include "stdlib.fc"

slice msg_body = in_msg_body~load_ref();
int op = msg_body~load_uint(32);
```

**Tolk:**
```tolk
import "common.tolk";
import "tvm-dicts.tolk";

slice msg_body = in_msg_body.load_ref();
int op = msg_body.load_uint(32);
```

---

### 5. **Performance**

| Metric | Tolk | FunC |
|--------|------|------|
| **Gas Consumption** | 30-50% lower | Baseline |
| **Optimization** | Better compiler optimizations | Standard optimizations |
| **Code Size** | More efficient bytecode | Larger bytecode typically |

**Performance Improvement:**
- Tolk's design and optimizations result in significantly more gas-efficient contracts
- Benchmarks show 30-50% reduction in gas costs
- Better compiler optimizations lead to smaller, faster contracts

---

### 6. **Developer Experience**

| Feature | Tolk | FunC |
|---------|------|------|
| **IDE Support** | Growing support | Established support |
| **Error Messages** | More descriptive | Basic |
| **Documentation** | New, actively developed | Mature, extensive |
| **Community** | Growing | Large, established |
| **Tooling** | Modern toolchain | Established tools |

---

## Fift: Low-Level Scripting Language

### **Purpose:**
- Low-level scripting for TON
- Assembly-like operations
- Testing and debugging
- Contract deployment scripts
- Direct TVM stack manipulation

### **Characteristics:**
- **Stack-based**: Operations work on a stack
- **Low-level**: Direct control over TVM operations
- **Scripting**: Used for deployment and testing
- **Not for contracts**: Typically not used for main contract logic

### **Typical Use Cases:**
1. Deployment scripts
2. Testing contract interactions
3. Debugging bytecode
4. Low-level operations not available in FunC/Tolk

**Example Fift Script:**
```fift
"TonUtil.fif" include
<{ SETCP0 DUP IFNOTRET // return if recv_internal
   DUP 85143 INT EQUAL OVER 78748 INT EQUAL OR IFJMP:<{ // "seqno" and "getSeqno" get-methods
     1 INT AND 1 INT SUB PUSHCONT:<{ 2DROP 0 INT }> 1 INT AND 1 INT SUB PUSHCONT:<{ 2DROP @ my_balance }> IFELSE
   }>
   ...
}>
```

---

## Migration Guide: FunC → Tolk

### Steps:
1. **Review differences** between FunC and Tolk syntax
2. **Explore reference contracts** in `tolk-bench` repository
3. **Use FunC-to-Tolk converter** for automated migration
4. **Test thoroughly** after conversion

### Key Conversion Patterns:

| FunC | Tolk |
|------|------|
| `(int, int) get_data()` | `struct Data { int a; int b; } method get_data() -> Data` |
| `cell ~store_uint(x, y)` | `cell.store_uint(x, y)` |
| `tuple return` | `struct return` |
| `#include "stdlib.fc"` | `import "common.tolk"` |

---

## When to Use Each Language

### **Use Tolk when:**
- ✅ Starting a new project
- ✅ Want modern syntax and type safety
- ✅ Need better performance (lower gas costs)
- ✅ Want clearer, more maintainable code
- ✅ Working on production contracts (2025+)

### **Use FunC when:**
- ✅ Working with existing codebases
- ✅ Need mature, well-documented language
- ✅ Team is familiar with C-style syntax
- ✅ Using established TON development tools

### **Use Fift when:**
- ✅ Writing deployment scripts
- ✅ Testing and debugging at low level
- ✅ Need direct TVM stack control
- ✅ Creating development/deployment tools

---

## Summary Table

| Feature | Tolk | FunC | Fift |
|---------|------|------|------|
| **Level** | High-level | High-level | Low-level |
| **Year Introduced** | 2025 | Original | Original |
| **Syntax Style** | TypeScript/Rust-like | C-like | Stack-based |
| **Structures** | ✅ Yes | ❌ No | N/A |
| **Gas Efficiency** | ⭐⭐⭐⭐⭐ (30-50% better) | ⭐⭐⭐ | N/A |
| **Learning Curve** | Moderate | Moderate | Steep |
| **Use Case** | Smart contracts | Smart contracts | Scripting/Deployment |
| **Recommendation** | 🟢 Use for new projects | 🟡 Legacy/maintenance | 🔵 Specialized use |

---

## Resources

- **Tolk Documentation**: https://docs.ton.org/v3/documentation/smart-contracts/tolk
- **FunC Documentation**: https://docs.ton.org/develop/func/overview
- **Fift Documentation**: https://docs.ton.org/develop/fift/overview
- **Migration Guide**: https://docs.ton.org/v3/documentation/smart-contracts/tolk/tolk-vs-func

---

## Conclusion

**For new TON smart contract development in 2025:**
- **Primary Choice**: **Tolk** - Modern, efficient, and designed for the future
- **Legacy Projects**: **FunC** - Still supported, use for existing codebases
- **Specialized Tasks**: **Fift** - For deployment scripts and low-level operations

Tolk represents the future of TON smart contract development, offering significant improvements in developer experience, code clarity, and performance while maintaining compatibility with the TON Virtual Machine (TVM).

