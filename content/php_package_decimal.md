---
title: 'tyhp/decimal for PHP'
---

`tyhp/decimal` builds an immutable `\Tyhp\Decimal` and does arithmetic with methods. Results stay decimals. PHP has no decimal operators, so every operation on this page is a method. The namespace is `Tyhp\`. It depends on `tyhp/core`.

## Install

PHP 8.2 or newer. No extension is required. The package picks a backend when the first operation runs. The package version is `0.4`:

```bash
composer require tyhp/decimal:805.0.4
```

Suggested extensions, in the order the package tries them:

| Extension | `getBackendName()` | Role |
|-----------|--------------------|------|
| `ext-decimal` | `decimal` | Preferred |
| `ext-bcmath` | `bcmath` | Used when `ext-decimal` is absent |
| `ext-gmp` | `gmp` | Used when neither of the above is loaded |
| none | `integer-scaled` | Pure PHP |

## Quick start

`\Tyhp\decimal($value)` is `new \Tyhp\Decimal($value)`. `multiply` returns a new decimal. Echoing it prints the digit string.

```php
require 'vendor/autoload.php';

echo \Tyhp\decimal('19.99')->multiply(3), "\n";
```

That prints `59.97`.

## Creating a value

`new \Tyhp\Decimal(float|int|string|\Tyhp\Contracts\DecimalConvertible|null $value = null, ?int $scale = null, int $roundingMode = \PHP_ROUND_HALF_UP)`.

`\Tyhp\decimal(float|int|string|\Tyhp\Contracts\DecimalConvertible|null $value = null): \Tyhp\Decimal` passes `$value` through and leaves scale and rounding at the defaults.

A string keeps the scale it was written with: `'5'`, `'5.0'`, and `'5.00'` compare equal and have scales 0, 1, and 2. Pass `$scale` to force one. A larger scale pads with zeros. A smaller scale rounds half up when `$roundingMode` is `\PHP_ROUND_HALF_UP`, and truncates for any other mode. A negative scale throws `\ValueError` (`Decimal scale must be 0 or greater`).

A non-numeric string throws `\InvalidArgumentException`. `null` is `0`. `new \Tyhp\Decimal(null, 2)` is `0.00`.

Build money from strings or integers. A float carries its binary rounding into the decimal: `new \Tyhp\Decimal(0.1)` is not the digits `0.1`.

Public readonly properties are `$value` (the digits), `$scale`, and `$roundingMode`.

## Arithmetic

Each method returns a new `\Tyhp\Decimal`. An operand may be a decimal, an int, a float, a numeric string, or an object that implements `\Tyhp\Contracts\DecimalConvertible`. The result keeps the rounding mode of the value you called the method on.

| Method | Result scale |
|--------|----------------|
| `add($operand)`, `subtract($operand)`, `multiply($operand)`, `modulo($operand)` | The larger scale of the two operands |
| `divide($operand, ?int $scale = null)` | The larger scale, unless you pass `$scale` |
| `power(int $exponent)` | The scale of the receiver. A negative exponent throws `\InvalidArgumentException`. |
| `sqrt(?int $scale = null)` | The receiver's scale, unless you pass `$scale` |
| `negate()`, `abs()` | The receiver's scale |

Digits past the result scale are dropped toward zero. `divide` by zero throws `\DivisionByZeroError` (`Cannot divide ... by zero`), which does not extend `\Exception`. Catch `\DivisionByZeroError` or `\Throwable`.

```php
$total = \Tyhp\decimal('10.00')->divide(3, 4);
$wide = \Tyhp\decimal('19.99')->withScale(4)->multiply('0.0825');
$money = $wide->round(2);
```

## Comparisons

`compareTo($other): int` is negative, zero, or positive. The predicates are ordinary bool methods: `equals`, `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, `isZero`, `isPositive`, `isNegative`.

`===` compares object identity. Use `equals`.

## Rounding and scale

`withScale(int $scale): \Tyhp\Decimal` changes scale. A negative scale throws `\ValueError`. Reducing the scale uses `$roundingMode`: half up for `\PHP_ROUND_HALF_UP`, truncate otherwise.

`round(int $precision = 0, int $mode = \PHP_ROUND_HALF_UP): \Tyhp\Decimal` uses PHP's rounding constants and does not read `$roundingMode`. A negative precision throws `\ValueError`.

`floor(): \Tyhp\Decimal` and `ceil(): \Tyhp\Decimal` return a scale of 0.

## Display

`__toString(): string` returns `$value`, which is what `echo` prints. `jsonSerialize(): string` returns the same digits, so `json_encode` emits a JSON string.

`format(int $decimals = 2, string $decimalSep = '.', string $thousandsSep = ','): string` rounds to `$decimals` and inserts separators.

## Aggregates

`zero(int $scale = 2)` and `one(int $scale = 2)` are static constructors. `min(\Tyhp\Decimal ...$values)`, `max`, `sum`, and `avg` take decimals. `sum` uses the largest input scale. `avg` uses the scale of that sum. An empty list throws `\InvalidArgumentException` (`At least one value is required`).

## Backends

`\Tyhp\Decimal::getBackendName(): string` returns `decimal`, `bcmath`, `gmp`, or `integer-scaled`, after the first operation has chosen one. `\Tyhp\Decimal::setBackend(\Tyhp\Backend\DecimalBackend $backend): void` replaces it. Application code usually leaves the choice alone.

## A type of your own

Implement `\Tyhp\Contracts\DecimalConvertible` and arithmetic methods will accept the object:

```php
final class Money implements \Tyhp\Contracts\DecimalConvertible
{
    public function __construct(private \Tyhp\Decimal $amount) {}

    public function __toDecimal(): \Tyhp\Decimal
    {
        return $this->amount;
    }
}
```

## Errors

| Exception | When |
|-----------|------|
| `\ValueError` | A scale or a rounding precision is negative. |
| `\InvalidArgumentException` | The constructor string is not numeric, or `power` is given a negative exponent. |
| `\DivisionByZeroError` | `divide` or `modulo` by zero. |

## Related

- [Packages for PHP](php_packages.md)
- [tyhp/core for PHP](php_package_core.md)
- [The tyhp/decimal Package](package_decimal.md) — the same package as used from Tyhp
