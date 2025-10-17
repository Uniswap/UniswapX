# HybridAuctionResolver

## Overview

HybridAuctionResolver implements Tribunal's hybrid Dutch + priority gas auction mechanism for UniswapX V4. It combines:

- **Dutch auction**: Price evolves over time according to a configurable price curve
- **Priority gas auction**: Filler priority fees adjust final prices dynamically

## Core Mechanism

We use Tribunal's implementation through importing the PriceCurveLib. Read more about the core mechanics in [their doc](https://github.com/Uniswap/Tribunal/blob/main/docs/PriceCurveLib-documentation.md).

### Cosigner Overrides

Optional cosigner can provide:

- `auctionTargetBlock`: Override the auction start block
- `supplementalPriceCurve`: Additional scaling factors to combine with base curve

## Test Coverage

To ensure we strictly follow the Tribunal's implementation, a large amount of tests have been migrated over and adapted to work with UniswapX.

## Test Mapping to Tribunal

All tests verify **identical outputs** to Tribunal by using the same `PriceCurveLib` and formulas.

### DeriveAmounts Tests (11 tests)

| HybridAuctionResolver Test                                           | Tribunal Test                                                        | Parameters                                            |
| -------------------------------------------------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------- |
| `test_DeriveAmounts_NoPriorityFee`                                   | `test_DeriveAmounts_NoPriorityFee`                                   | No priority fee above baseline                        |
| `test_DeriveAmounts_ExactOut`                                        | `test_DeriveAmounts_ExactOut`                                        | scalingFactor = 0.5e18, priorityFee = 2 wei           |
| `test_DeriveAmounts_ExactIn`                                         | `test_DeriveAmounts_ExactIn`                                         | scalingFactor = 1.5e18, priorityFee = 2 wei           |
| `test_DeriveAmounts_ExtremePriorityFee`                              | `test_DeriveAmounts_ExtremePriorityFee`                              | scalingFactor = 1.5e18, priorityFee = 10 wei          |
| `test_DeriveAmounts_RealisticExactIn`                                | `test_DeriveAmounts_RealisticExactIn`                                | scalingFactor = 1.0000000001e18, priorityFee = 5 gwei |
| `test_DeriveAmounts_RealisticExactOut`                               | `test_DeriveAmounts_RealisticExactOut`                               | scalingFactor = 0.9999999999e18, priorityFee = 5 gwei |
| `test_DeriveAmounts_WithPriceCurve`                                  | `test_DeriveAmounts_WithPriceCurve`                                  | 3-segment curve, fill at block 5                      |
| `test_DeriveAmounts_WithPriceCurve_Dutch`                            | `test_DeriveAmounts_WithPriceCurve_Dutch`                            | Dutch auction 1.2x→1.0x over 10 blocks                |
| `test_DeriveAmounts_WithPriceCurve_Dutch_nonNeutralEndScalingFactor` | `test_DeriveAmounts_WithPriceCurve_Dutch_nonNeutralEndScalingFactor` | Dutch auction ending at 1.1x (non-neutral)            |
| `test_DeriveAmounts_WithPriceCurve_ReverseDutch`                     | `test_DeriveAmounts_WithPriceCurve_ReverseDutch`                     | Reverse Dutch 0.8x→1.0x over 20 blocks                |
| `test_DeriveAmounts_InvalidTargetBlockDesignation`                   | `test_DeriveAmounts_InvalidTargetBlockDesignation`                   | Price curve without target block (revert)             |

### Documentation Tests (6 tests)

| HybridAuctionResolver Test           | Tribunal Test                | Scenario                               |
| ------------------------------------ | ---------------------------- | -------------------------------------- |
| `test_Doc_LinearDecay_DutchAuction`  | `test_LinearDecay`           | 0.8x→1.0x over 100 blocks              |
| `test_Doc_StepFunctionWithPlateaus`  | `test_StepFunction`          | 1.5x→1.2x→1.0x with zero-duration drop |
| `test_Doc_AggressiveInitialDiscount` | `test_AggressiveDiscount`    | 0.5x→0.9x multi-phase                  |
| `test_Doc_ReverseDutchAuction`       | `test_ReverseDutch`          | 2.0x→1.0x over 200 blocks              |
| `test_Doc_ComplexMultiPhaseCurve`    | `test_ComplexCurve`          | 0.5x→0.7x→0.8x in 3 phases             |
| `test_Doc_*_ExceedsDuration`         | (corresponding revert tests) | Tests for duration exceeded reverts    |

### Edge Cases (13 tests)

| HybridAuctionResolver Test                    | Tribunal Test                | Edge Case                     |
| --------------------------------------------- | ---------------------------- | ----------------------------- |
| `test_EmptyPriceCurve_ReturnsNeutralScaling`  | `test_EmptyPriceCurve`       | No price curve (neutral 1.0x) |
| `test_ZeroDuration_InstantaneousPricePoint`   | `test_ZeroDuration`          | Zero-duration elements        |
| `test_ZeroScalingFactor_ExactOut`             | `test_ZeroScaling`           | Scaling factor = 0            |
| `test_RevertsExceedingTotalBlockDuration`     | `test_ExceedsDuration`       | Fill beyond curve duration    |
| `test_RevertsInconsistentScalingDirections`   | `test_InconsistentDirection` | Curve crosses 1.0x (invalid)  |
| `test_RevertsInvalidAuctionBlock`             | `test_InvalidAuctionBlock`   | Future auction start block    |
| `test_StepFunctionWithPlateaus`               | `test_StepFunction`          | 3-segment step function       |
| `test_InvertedAuction_PriceIncreasesOverTime` | `test_InvertedAuction`       | Price increases 0.5x→1.0x     |
| ... and 5 more                                | ...                          | Various edge cases            |

### Multiple Zero Duration (2 tests)

| HybridAuctionResolver Test                              | Tribunal Test            | Scenario                                 |
| ------------------------------------------------------- | ------------------------ | ---------------------------------------- |
| `test_MultipleConsecutiveZeroDuration_DetailedBehavior` | `test_TwoZeroDuration`   | Two consecutive zero-duration elements   |
| `test_ThreeConsecutiveZeroDuration`                     | `test_ThreeZeroDuration` | Three consecutive zero-duration elements |

### Priority Fee Tests (2 tests)

Custom tests verifying priority fee mechanism:

- `test_PriorityFee_ExactIn_IncreasesWithGas`: Output increases with priority fee
- `test_PriorityFee_ExactOut_DecreasesWithGas`: Input decreases with priority fee

### Cosigner Tests (3 tests)

Custom tests verifying cosigner functionality:

- `test_CosignerOverrideAuctionTargetBlock`: Cosigner overrides start block
- `test_CosignerSupplementalPriceCurve`: Cosigner adds supplemental curve
- `test_RevertsWrongCosigner`: Invalid cosigner signature reverts

### Multiple Outputs (1 test)

Custom test verifying multiple output tokens:

- `test_MultipleOutputs_ExactIn`: Two output tokens scaled correctly

## Verification Approach

### How We Verify Identical Behavior to Tribunal

1. **Same Library**: Both implementations use `PriceCurveLib.getCalculatedValues()`

   - Identical interpolation logic
   - Identical boundary checks
   - Identical scaling calculations

2. **Same Test Parameters**:

   - Use EXACTLY the same inputs as Tribunal tests
   - Same price curves, blocks, scaling factors, priority fees

3. **Same Expected Values**:

   - Assert EXACTLY the same outputs as Tribunal
   - Tests pass → we produce SAME output as Tribunal

4. **Same Arithmetic**:
   ```solidity
   // Exact-in:
   scalingMultiplier = currentScalingFactor + ((scalingFactor - 1e18) * priorityFee)
   // Exact-out:
   scalingMultiplier = currentScalingFactor - ((1e18 - scalingFactor) * priorityFee)
   ```
   No division by BASE_SCALING_FACTOR in priority fee term (mulWad handles it)

## Key Differences from Tribunal

1. **Order Structure**:

   - Tribunal: `Fill` struct within `Mandate`
   - HybridAuctionResolver: `HybridOrder` for UniswapX V4

2. **Settlement**:

   - Tribunal: Settles via TheCompact
   - HybridAuctionResolver: Settles via UniswapX V4 Reactor

3. **Same Core Logic**:
   - Both use `PriceCurveLib` for price curve interpolation
   - Both use identical priority fee formulas
   - Both produce identical amounts for identical parameters

## Running Tests

```bash
# Run all HybridAuctionResolver tests
forge test --match-contract HybridAuctionResolverTest

# Run specific test category
forge test --match-test test_Doc_
forge test --match-test test_DeriveAmounts_

# Run with verbosity
forge test --match-contract HybridAuctionResolverTest -vv
```
