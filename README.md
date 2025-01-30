# Art Token Lending Protocol

A decentralized lending protocol built on Stacks that enables users to use their art tokens as collateral for loans. The protocol implements a secure lending mechanism with flexible loan-to-value (LTV) ratios, liquidation features, and emergency controls.

## Overview

This protocol allows users to:
- Lock art tokens as collateral
- Take out loans against their art token collateral
- Repay loans to reclaim their collateral
- Withdraw excess collateral when their position is over-collateralized

The system includes safety mechanisms such as:
- Minimum LTV ratio requirements
- Price oracle integration for real-time art token valuations
- Liquidation functionality for under-collateralized positions
- System pause functionality for emergency situations

## Key Features

### Collateral Management
- Users can lock art tokens as collateral using `lock-art-collateral`
- Excess collateral can be withdrawn using `withdraw-art-collateral`
- Real-time collateral value calculations based on oracle prices

### Lending Operations
- Users can borrow against their collateral using `take-loan`
- Loans can be repaid using `repay-loan`
- Automatic collateral release upon loan repayment

### Risk Management
- Dynamic LTV ratio requirements (minimum 150% by default)
- Price oracle integration for accurate collateral valuation
- Liquidation mechanism for under-collateralized positions
- System pause capability for emergency situations

### Price Oracle
- Real-time price updates from authorized oracle
- Last update timestamp tracking
- Price validity checks

## Public Functions

### Collateral Operations
```clarity
(define-public (lock-art-collateral (art-amount uint)))
(define-public (withdraw-art-collateral (art-amount uint)))
```

### Loan Operations
```clarity
(define-public (take-loan (amount uint)))
(define-public (repay-loan (amount uint)))
```

### Liquidation
```clarity
(define-public (liquidate (user principal)))
```

### Fee Management
```clarity
(define-public (claim-fees))
```

## Read-Only Functions

- `get-art-collateral`: Check collateral balance for a user
- `get-loan-balance`: Check loan balance for a user
- `calculate-collateral-value`: Calculate current value of art tokens
- `check-ltv-ratio`: Get current loan-to-value ratio for a user
- `is-collateral-sufficient`: Check if collateral covers a proposed loan
- `get-price`: Get current art token price
- `get-last-update`: Get timestamp of last price update

## Administrative Functions

### System Control
```clarity
(define-public (pause-system))
(define-public (unpause-system))
```

### Parameter Adjustment
```clarity
(define-public (adjust-ltv-ratio (new-ratio uint)))
(define-public (update-price (new-price uint)))
```

## Error Codes

- `u100`: Unauthorized (owner-only function)
- `u101`: Invalid price input

## Security Considerations

1. **Price Oracle Security**: The system relies on accurate price feeds. Only the contract owner can update prices.
2. **Liquidation Risk**: Positions can be liquidated if they fall below the minimum LTV ratio.
3. **Emergency Controls**: The system can be paused by the contract owner in case of emergencies.

## Getting Started

To interact with the protocol:

1. Lock art tokens as collateral using `lock-art-collateral`
2. Take out a loan using `take-loan` (ensure sufficient collateral)
3. Monitor your position's health using `check-ltv-ratio`
4. Repay loans using `repay-loan` to reclaim collateral
5. Withdraw excess collateral using `withdraw-art-collateral` when over-collateralized

## Dependencies

- Stacks blockchain
- Clarity smart contract language