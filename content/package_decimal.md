---
title: 'The tyhp/decimal Package'
---

`tyhp/decimal` provides `\Tyhp\Decimal`, an immutable arbitrary-precision decimal number, and the `\Tyhp\decimal()` helper that creates one. It is the runtime behind the Tyhp `decimal` type. Use it wherever binary floating point is not good enough: prices, invoice totals, tax, exchange rates, account balances, and measurements that must round-trip exactly through a database or an API.

A `Decimal` stores its digits as a string, so `0.1 + 0.2` is exactly `0.3`. Arithmetic runs on the fastest arbitrary-precision extension that PHP has loaded (`ext-decimal`, `ext-bcmath`, or `ext-gmp`), with a pure-PHP fallback when none is available.

This page is the package reference: installation, how scale and rounding work, every public class and method, the backends, and worked recipes. For the `decimal` type as a language feature, see [New and Changed Types](tyhp_0150_newTypes.md). For how operators compile in general, see [Operator Overloads](tyhp_1600_operatorOverloads.md).

## Installing

`tyhp build` reports `tyhp/decimal` as a needed runtime package as soon as your code uses `decimal`, and writes the pin for you when `build.updateComposer` is enabled. To add it yourself, pick the prefix that matches `output.phpVersion` in `tyhp.json`:

```bash
composer require tyhp/decimal:804.0.*
```

The package needs PHP 8.2 or later and `tyhp/core`, which Composer installs with it. [Composer Runtime Packages](project_composerPackages.md) explains the `80N.X.Y` version scheme and how libraries should pin it.

No PHP extension is required, but install one for production. The package picks a backend automatically when the first decimal operation runs:

| Loaded extension | Backend name | Notes |
|------------------|--------------|-------|
| `ext-decimal` (PECL php-decimal / mpdecimal) | `decimal` | Preferred |
| `ext-bcmath` | `bcmath` | Bundled with most PHP builds |
| `ext-gmp` | `gmp` | Used only when neither of the above is loaded |
| none | `integer-scaled` | Pure PHP, slower; raises a one-time `E_USER_NOTICE` |

See [Backends](#backends) for details.

## Quick start

```tyhp
<?tyhp

use Tyhp\Decimal;

decimal $price = \Tyhp\decimal('19.99');
decimal $subtotal = $price * 3;                   // 59.97
decimal $total = $subtotal + '4.50';              // 64.47

echo $total, "\n";                                // 64.47
echo $total->format(2), "\n";                     // 64.47
echo \json_encode(['total' => $total]), "\n";     // {"total":"64.47"}

if ($total > Decimal::zero()) {
    echo "Amount due\n";
}
```

Arithmetic and comparison operators work on `decimal` values and call the `Decimal` methods for you (see [Operators](#operators)). The rest of this page explains the rules that decide how many digits each result keeps, because those rules matter for money.

## Core concepts

### Values are immutable

Every operation returns a new `Decimal`. The original is never changed, so you can share instances freely and reuse them as constants.

```tyhp
<?tyhp

decimal $balance = \Tyhp\decimal('10.00');
decimal $bigger = $balance + 5;   // $balance is still 10.00
$balance += 5;                    // assigns a new Decimal: 15.00
```

### Value and scale

A `Decimal` has two readonly parts: `value`, the digits as a string such as `'19.99'`, and `scale`, the number of digits after the decimal point. A value created from a string keeps the scale it was written with, so `'5'`, `'5.0'`, and `'5.00'` are equal but have scales 0, 1, and 2. Scale controls how many digits arithmetic results keep and how the value prints.

### How each result's scale is chosen

| Operation | Result scale |
|-----------|--------------|
| `$a + $b`, `$a - $b`, `$a * $b`, `$a % $b` (`add`, `subtract`, `multiply`, `modulo`) | The larger scale of the two operands |
| `$a / $b` (`divide($x)`) | The larger scale of the two operands, unless you call `divide($x, $scale)` |
| `$a ** $n` (`power($n)`), `sqrt()` | The scale of the value you call it on, unless you pass `$scale` to `sqrt()` |
| `-$a` (`negate`), `abs` | Unchanged |
| `round($precision)` | `$precision` |
| `floor`, `ceil` | 0 |
| `withScale($n)` | `$n` |
| `sum` | The largest scale among the inputs |
| `avg` | The scale of the sum |

### Arithmetic truncates

When an exact result has more digits than the result scale, the extra digits are dropped (truncated toward zero). Nothing is rounded until you ask for it:

```tyhp
<?tyhp

decimal $ten = \Tyhp\decimal('10');
decimal $tenCents = \Tyhp\decimal('10.00');
decimal $two = \Tyhp\decimal('2.00');
decimal $quarter = \Tyhp\decimal('1.25');

$ten / 3;                  // 3          (scale 0)
$tenCents / 3;             // 3.33       (scale 2)
$ten->divide(3, 4);        // 3.3333     (scale 4; the operator form has no scale argument)
$two / 3;                  // 0.66       (truncated, not 0.67)
$quarter * $quarter;       // 1.56       (exact result is 1.5625)
```

For money, the safe pattern is to widen the scale before multiplying or dividing, then round once at the end:

```tyhp
<?tyhp

decimal $net = \Tyhp\decimal('59.97');
decimal $rate = \Tyhp\decimal('0.08');

decimal $truncated = $net * $rate;                             // 4.79  (scale 2, truncated from 4.7976)
decimal $rounded = ($net->withScale(6) * $rate)->round(2);     // 4.80
```

### Rounding modes

`round()` takes PHP's standard rounding constants. `withScale()` and the constructor, when they reduce the scale, round half up if the value's `roundingMode` property is `\PHP_ROUND_HALF_UP` and truncate for any other mode.

| Constant | Rounds a tie (…5) | Example: `2.545` to 2 places | Example: `-2.555` to 2 places |
|----------|-------------------|------------------------------|-------------------------------|
| `\PHP_ROUND_HALF_UP` (default) | Away from zero | `2.55` | `-2.56` |
| `\PHP_ROUND_HALF_DOWN` | Toward zero | `2.54` | `-2.55` |
| `\PHP_ROUND_HALF_EVEN` | To the even digit (banker's rounding) | `2.54` | `-2.56` |
| `\PHP_ROUND_HALF_ODD` | To the odd digit | `2.55` | `-2.55` |

A value is a tie only when every discarded digit is a `5` followed by zeros. `2.5451` is above a tie, so it rounds up to `2.55` in every mode, while `2.545` is a tie and follows the mode. Any other mode value truncates.

### Accepted input

Anything typed `\Tyhp\DecimalCoercible` (or `null`) can become a `Decimal`:

| Input | Result |
|-------|--------|
| `string` | Leading and trailing whitespace is trimmed. The rest must be an optional `-`, one or more digits, and optionally `.` followed by one or more digits. An empty string is `0`. Anything else throws `\InvalidArgumentException`. |
| `int` | The exact integer, scale 0. |
| `float` | Converted with 20 fractional digits, then trailing zeros are removed. `NaN` and `INF` throw `\InvalidArgumentException`. |
| `\Tyhp\Contracts\DecimalConvertible` | The value returned by its `__toDecimal()`. |
| `null` | `0`. With `$scale` passed to the constructor, `0` at that scale (`new Decimal(null, 2)` is `0.00`); otherwise scale 0. |

Strings that the parser rejects include `'+1'`, `'.5'`, `'5.'`, `'1e3'`, `'1,000'`, and `'1 000'`. Normalize user input before constructing a value (see [Parsing user input](#parsing-user-input)).

:::danger
Do not create money values from floats. A float carries its binary rounding error into the decimal: `new Decimal(0.1)` is `0.10000000000000000555` with scale 20, and `new Decimal(19.99)` is `19.98999999999999843681`. Always pass strings (or integers) for values that must be exact. The same applies to a float on either side of an operator: `$amount + 0.01` adds `0.01000000000000000021`, so write `$amount + '0.01'`.
:::

## Using `decimal` in Tyhp code

### The `decimal` type

In Tyhp, `decimal` and `\Tyhp\Decimal` name the same type, and `decimal` needs no import in namespaced files. Write `decimal` in type positions (parameters, properties, returns, locals) and the class name where you need the class itself (`new`, static calls, `instanceof`): either `\Tyhp\Decimal` or `Decimal` after `use Tyhp\Decimal;`. Both compile to `\Tyhp\Decimal` in PHP.

```tyhp
<?tyhp

use Tyhp\Decimal;

final class Product
{
    public function __construct(
        public readonly string $sku,
        public readonly decimal $price,
    ) {}

    public function discounted(decimal $percent): decimal {
        decimal $factor = Decimal::one() - $percent->divide(100, 4);
        return ($this->price->withScale(4) * $factor)->round(2);
    }
}
```

### Creating values

There are three ways to create a value:

- `\Tyhp\decimal($value)` accepts any `DecimalCoercible` or `null`.
- `new \Tyhp\Decimal($value, $scale, $roundingMode)` does the same and also lets you fix the scale or the rounding mode.
- `(decimal) $expr` converts an expression whose type is `string`, `int`, `float`, or a union of those, and compiles to `\Tyhp\Decimal::__from($expr)`. The result is a `decimal`, so it can be assigned, passed, or used as an operand: `decimal $total = (decimal) $input + 1;`. A string that is not a valid number throws `\InvalidArgumentException` when the cast runs. A cast of a `float` keeps the float's binary error. Casting a value that is already `decimal` does nothing and reports the warning **TYHP4205**.

Any other source type is an error (**TYHP4008**): `bool`, `null`, arrays, nullable types such as `?string`, and objects that implement `DecimalConvertible`. Use `\Tyhp\decimal($value)` for a `DecimalConvertible` object, and check a nullable value for `null` first.

The compiler also converts a `string`, `int`, or `float` to `decimal` for you in two places: call arguments to a `decimal` parameter, and `return` values in a function that returns `decimal`. A `Decimal` passed to a `string` parameter is converted with `__toString()`. Other positions need an explicit conversion. A plain assignment such as `decimal $x = '2.5';`, a property assignment, and an array element are errors (**TYHP4008**); write `decimal $x = \Tyhp\decimal('2.5');`.

```tyhp
<?tyhp

function charge(decimal $amount): void {
    // ...
}

function defaultFee(): decimal {
    return '2.50';       // compiles to return \Tyhp\Decimal::__from('2.50')
}

charge('19.99');         // compiles to charge(\Tyhp\Decimal::__from('19.99'))
charge(20);              // compiles to charge(\Tyhp\Decimal::__from(20))

string $input = '99.95';
decimal $parsed = (decimal) $input;   // 99.95
```

### Operators

`\Tyhp\Decimal` declares operator overloads, so use the operators in your code instead of calling `add()`, `multiply()`, `lessThan()` and the other named methods. The compiler rewrites each operator into the matching call, and the checker types the result: `decimal $total = $a + $b;` and `if ($a < $b)` type-check as written. At least one operand must be a `Decimal`; the other may be a `string`, `int`, or `float`, which is converted to a `Decimal` first. The right operand can also be any other `DecimalCoercible` value: a union such as `float|int|string` or `int|string`, a value typed `\Tyhp\DecimalCoercible`, or an object of a class that implements `\Tyhp\Contracts\DecimalConvertible`. A class that declares `operator convert(self $value): decimal` counts as `DecimalConvertible`, so its objects work as the right operand directly. Operators can be chained and nested (`$a + $b + $c`, `$a * ($b + $c)`), and the left operand can be a call result (`\Tyhp\decimal('2') + 1`).

```tyhp
<?tyhp

decimal $price = \Tyhp\decimal('19.99');
decimal $subtotal = $price * 3;                      // 59.97
decimal $discounted = $subtotal - '5.00';            // 54.97
$discounted += '0.03';                               // 55.00
$discounted *= 2;                                    // 110.00
decimal $remaining = 150 - $discounted;              // 40.00

if ($discounted >= 100 && $discounted != $subtotal) {
    echo -$discounted, "\n";                         // -110.00
}
```

| Expression | Same as | Result type |
|------------|---------|-------------|
| `$a + $b` | `$a->add($b)` | `decimal` |
| `$a - $b` | `$a->subtract($b)` | `decimal` |
| `$a * $b` | `$a->multiply($b)` | `decimal` |
| `$a / $b` | `$a->divide($b)` (default scale) | `decimal` |
| `$a % $b` | `$a->modulo($b)` | `decimal` |
| `$a ** $n` | `$a->power($n)` (`$a` must be a `Decimal`, `$n` an `int`) | `decimal` |
| `-$a` | `$a->negate()` | `decimal` |
| `+$a` | `(float) $a->value` | `float` |
| `$a == $b` / `$a != $b` | `$a->equals($b)` / its negation | `bool` |
| `$a < $b` / `$a <= $b` / `$a > $b` / `$a >= $b` | `lessThan` / `lessThanOrEqual` / `greaterThan` / `greaterThanOrEqual` | `bool` |
| `$a <=> $b` | `$a->compareTo($b)` | `int` (-1, 0, 1) |
| `$a += $b` and other compound forms | The matching binary operator | `decimal` |
| `(int) $a` / `(float) $a` / `(string) $a` | `__toInt()` / `__toFloat()` / `__toString()` | `int` / `float` / `string` |

`"Total: {$a}"` and `echo $a` print the value through `__toString()`.

Keep these limits in mind:

- **The operators have no scale argument.** `$a / $b` divides at the larger of the two scales. Call `$a->divide($b, $scale)` when you need more digits, and `round()`, `withScale()`, `power()`, and `sqrt()` for the operations that have no operator.
- **A number or string on the left works for every operator except `**`.** `5 + $a`, `'1.00' * $a`, and `100 > $a` convert the left value to a `Decimal` (with the scale it was written with) before the operation. `**` needs a `Decimal` base and an `int` exponent, so `2 ** $a` is a compile error (**TYHP4029**).
- **Floats carry their binary error.** `$a * 0.1` multiplies by `0.1000000000000000055…`. Write `$a * '0.1'`.
- **`===` and `!==`** compare object identity, as in PHP. Two equal decimals are usually different instances. Use `==` (or `equals()`).

## API reference

### The `\Tyhp\decimal()` function

:::member[function \Tyhp\decimal(float|int|string|\Tyhp\Contracts\DecimalConvertible|null $value = null): decimal]
Creates a `Decimal` from `$value` with the default scale (the digits as written) and `\PHP_ROUND_HALF_UP`. Equivalent to `new \Tyhp\Decimal($value)`. Throws `\InvalidArgumentException` for input the parser rejects (see [Accepted input](#accepted-input)).

```tyhp
<?tyhp

decimal $a = \Tyhp\decimal('19.99');   // scale 2
decimal $b = \Tyhp\decimal(42);        // scale 0
decimal $c = \Tyhp\decimal();          // 0
```
:::

### `\Tyhp\Decimal`

`final class Decimal implements \Tyhp\Contracts\DecimalConvertible, \Tyhp\Contracts\FloatConvertible, \Tyhp\Contracts\IntConvertible, \Tyhp\Contracts\StringConvertible, \JsonSerializable`

An immutable decimal number. In Tyhp code, prefer the operators described in [Operators](#operators); each method below says which operator it backs. Methods that take an operand accept `\Tyhp\DecimalCoercible`, so `$price->add('1.50')`, `$price->add(2)`, and `$price->add($otherDecimal)` all work (and so do `$price + '1.50'`, `$price + 2`, and `$price + $otherDecimal`). Results keep the rounding mode of the value the method is called on.

#### Properties

:::member[public readonly string $value]
The digits as a string, for example `'19.99'` or `'-0.50'`. String input is stored as written after trimming whitespace, so `new Decimal('007.50')` keeps its leading zeros. This is the form to store in a database or send in JSON.
:::

:::member[public readonly int $scale]
The number of digits after the decimal point.
:::

:::member[public readonly int $roundingMode]
The rounding mode used when `withScale()` or the constructor reduces the scale. Arithmetic results inherit it from the left operand. `round()` and `format()` do not use it.
:::

#### Construction

:::member[public function __construct(\Tyhp\DecimalCoercible|null $value = null, ?int $scale = null, int $roundingMode = \PHP_ROUND_HALF_UP)]
Creates a decimal.

- `$value` — see [Accepted input](#accepted-input).
- `$scale` — `null` keeps the digits as written. A larger scale pads with zeros (`new Decimal('1.5', 4)` is `1.5000`). A smaller scale removes digits: with `\PHP_ROUND_HALF_UP` the last kept digit is rounded half up (`new Decimal('1.005', 2)` is `1.01`, and `new Decimal('1.7', 0)` is `2`). With any other rounding mode, extra digits are truncated. Must be 0 or greater.
- `$roundingMode` — stored on the value (see `roundingMode`).

When `$value` is a `DecimalConvertible` and `$scale` is `null`, the value and its scale are copied unchanged. When you pass `$scale`, the value is rescaled exactly like string input.

**Throws** `\InvalidArgumentException` with the message `Cannot create Decimal from non-numeric string: …` or `Cannot create Decimal from NaN or Inf float value`. A negative `$scale` throws `\ValueError` with the message `Decimal scale must be 0 or greater, -1 given`.

```tyhp
<?tyhp

use Tyhp\Decimal;

$price = new Decimal('19.99');                           // 19.99, scale 2
$cents = new Decimal('1.005', 2);                        // 1.01
$truncating = new Decimal('1.005', 2, \PHP_ROUND_HALF_EVEN); // 1.00
```
:::

#### Arithmetic

:::member[public function add(\Tyhp\DecimalCoercible $operand): self]
Returns `$this + $operand` at the larger of the two scales. Operator: `$a + $b`.

```tyhp
<?tyhp

decimal $a = \Tyhp\decimal('1.5');
decimal $sum = $a + 2;      // 3.5
```
:::

:::member[public function subtract(\Tyhp\DecimalCoercible $operand): self]
Returns `$this - $operand` at the larger of the two scales. Operator: `$a - $b`.
:::

:::member[public function multiply(\Tyhp\DecimalCoercible $operand): self]
Returns `$this * $operand` at the larger of the two scales, truncated. Operator: `$a * $b`. The exact product usually has more digits than either operand. Widen the scale first with `withScale()` when you need those digits.

```tyhp
<?tyhp

decimal $price = \Tyhp\decimal('19.99');
decimal $tax = $price * '0.0825';                          // 1.6491 (exact: 1.649175)
decimal $exact = $price->withScale(6) * '0.0825';          // 1.649175
```
:::

:::member[public function divide(\Tyhp\DecimalCoercible $operand, ?int $scale = null): self]
Returns `$this / $operand`, truncated to `$scale` digits. Operator: `$a / $b`, which uses the default scale. Call the method only when you need to choose `$scale`. When `$scale` is `null`, the result uses the larger of the two operand scales, so dividing two whole numbers gives a whole number (`10 / 3` is `3`). Pass `$scale` whenever the quotient can be fractional.

**Throws** `\DivisionByZeroError` (`Cannot divide … by zero`) when `$operand` is zero. `\DivisionByZeroError` is an `\Error`, not an `\Exception`.

```tyhp
<?tyhp

decimal $whole = \Tyhp\decimal('100');
decimal $cents = \Tyhp\decimal('100.00');

$whole->divide(3, 2);     // 33.33
$cents / 3;               // 33.33
$whole->divide('8', 3);   // 12.500
```
:::

:::member[public function modulo(\Tyhp\DecimalCoercible $operand): self]
Returns the remainder of `$this / $operand` at the larger of the two scales. Operator: `$a % $b`. The sign follows the dividend: `-7 % 3` is `-1`, and `7.5 % 2` is `1.5`.

**Throws** `\DivisionByZeroError` (`Modulo by zero`) when `$operand` is zero.
:::

:::member[public function power(int $exponent): self]
Returns `$this` raised to `$exponent` at the scale of `$this`, truncated. Operator: `$a ** $n`. When `$a` is `1.10`, `$a ** 3` is `1.33`; widen the scale first for more digits (`$a->withScale(6) ** 3` is `1.331000`). `$a ** 0` is `1.00`.

**Throws** `\InvalidArgumentException` (`Negative exponents are not supported`) when `$exponent` is negative. For a reciprocal, use `Decimal::one()->divide($x, $scale)`.
:::

:::member[public function negate(): self]
Returns `-$this` at the same scale. Negating zero returns zero. Operator: `-$a`.
:::

:::member[public function abs(): self]
Returns the absolute value at the same scale.
:::

:::member[public function sqrt(?int $scale = null): self]
Returns the square root, truncated to `$scale` digits (default: the scale of `$this`). `\Tyhp\decimal('2')->sqrt()` is `1`; `\Tyhp\decimal('2')->sqrt(6)` is `1.414213`.

**Throws** `\InvalidArgumentException` (`Square root of a negative number is not supported`) when `$this` is negative.
:::

#### Comparison

All comparisons are exact. Both sides are compared at the larger of their scales, so trailing zeros never matter: `'5.00'` equals `'5'`.

:::member[public function compareTo(\Tyhp\DecimalCoercible $other): int]
Returns `-1` when `$this` is less than `$other`, `0` when they are equal, and `1` when it is greater. Operator: `$a <=> $b`. Use it as a sort comparator: `\usort($prices, fn(Decimal $a, Decimal $b): int => $a <=> $b);`.
:::

:::member[public function equals(\Tyhp\DecimalCoercible $other): bool]
`true` when the two values are numerically equal, regardless of scale. Operators: `$a == $b`, and `$a != $b` for the negation.
:::

:::member[public function greaterThan(\Tyhp\DecimalCoercible $other): bool]
`true` when `$this > $other`. Operator: `$a > $b`.
:::

:::member[public function greaterThanOrEqual(\Tyhp\DecimalCoercible $other): bool]
`true` when `$this >= $other`. Operator: `$a >= $b`.
:::

:::member[public function lessThan(\Tyhp\DecimalCoercible $other): bool]
`true` when `$this < $other`. Operator: `$a < $b`.
:::

:::member[public function lessThanOrEqual(\Tyhp\DecimalCoercible $other): bool]
`true` when `$this <= $other`. Operator: `$a <= $b`.
:::

:::member[public function isZero(): bool]
`true` for any zero, including `0.00` and `-0`.
:::

:::member[public function isPositive(): bool]
`true` when the value is greater than zero.
:::

:::member[public function isNegative(): bool]
`true` when the value is less than zero. `-0` is not negative.
:::

#### Scale and rounding

:::member[public function withScale(int $scale): self]
Returns the same number with a different scale. Increasing the scale pads with zeros (`5.1` becomes `5.1000`). Decreasing it follows the constructor's rule: half up when `roundingMode` is `\PHP_ROUND_HALF_UP` (`1.25` becomes `1.3`, and `1.75` becomes `2` at scale 0), and truncation for any other rounding mode. A negative `$scale` throws `\ValueError`.

Use `withScale()` to widen a value before multiplying, dividing, or raising to a power, and `round()` to reduce a value to its final precision.
:::

:::member[public function round(int $precision = 0, int $mode = \PHP_ROUND_HALF_UP): self]
Rounds to `$precision` digits after the decimal point using `$mode` (see [Rounding modes](#rounding-modes)). The result's scale is `$precision`. When the value already has `$precision` digits or fewer, it is padded instead (`1.5` rounded to 4 places is `1.5000`). A negative `$precision` throws `\ValueError`. This method ignores `roundingMode`.

```tyhp
<?tyhp

\Tyhp\decimal('2.555')->round(2);                         // 2.56
\Tyhp\decimal('-2.555')->round(2);                        // -2.56
\Tyhp\decimal('2.545')->round(2, \PHP_ROUND_HALF_EVEN);   // 2.54
\Tyhp\decimal('9.999')->round(2);                         // 10.00
```
:::

:::member[public function floor(): self]
Rounds toward negative infinity to a whole number (scale 0). `3.7` becomes `3`; `-3.2` becomes `-4`.
:::

:::member[public function ceil(): self]
Rounds toward positive infinity to a whole number (scale 0). `3.2` becomes `4`; `-3.7` becomes `-3`.
:::

#### Conversion and output

:::member[public function format(int $decimals = 2, string $decimalSep = '.', string $thousandsSep = ','): string]
Rounds to `$decimals` places with `\PHP_ROUND_HALF_UP` and returns a display string with grouped thousands. Pass `''` as `$thousandsSep` to disable grouping. With `$decimals` set to 0, no decimal separator is printed. A value that rounds to zero prints without a minus sign. For locale-aware currency formatting, pass the result of `round()` to `\NumberFormatter` from `ext-intl`.

```tyhp
<?tyhp

decimal $d = \Tyhp\decimal('1234567.891');
$d->format();                // 1,234,567.89
$d->format(2, ',', '.');     // 1.234.567,89
$d->format(2, '.', '');      // 1234567.89
\Tyhp\decimal('-1234.5')->format(0);   // -1,235
```
:::

:::member[public function jsonSerialize(): string]
Returns `value`. `\json_encode()` therefore writes a decimal as a JSON **string** (`"19.99"`), which keeps every digit. Clients that need a number must parse it themselves.
:::

:::member[public function __toString(): string]
Returns `value` unchanged (same scale, same leading zeros). Used by `(string) $d`, string interpolation, `echo`, and string concatenation.
:::

:::member[public function __toInt(): int]
Returns the integer part, truncated toward zero (`-42.9` becomes `-42`). Used by `(int) $d` in Tyhp. Values outside the `int` range follow PHP's string-to-int conversion.
:::

:::member[public function __toFloat(): float]
Returns the nearest `float`. Used by `(float) $d` in Tyhp. The conversion can lose precision; use it only for display, charts, or APIs that require floats.
:::

:::member[public function __toDecimal(): self]
Returns `$this`. This satisfies `\Tyhp\Contracts\DecimalConvertible`, so a `Decimal` can go anywhere a `DecimalConvertible` is accepted.
:::

#### Static helpers

:::member[public static function zero(int $scale = 2): self]
Returns zero at `$scale` (default `0.00`). A convenient starting value for sums of money.
:::

:::member[public static function one(int $scale = 2): self]
Returns one at `$scale` (default `1.00`).
:::

:::member[public static function min(Decimal ...$values): self]
Returns the smallest of the arguments, unchanged (it keeps its own scale). When several are equal, the first one wins. Arguments must be `Decimal` instances; spread an array with `Decimal::min(...$prices)`.

**Throws** `\InvalidArgumentException` (`At least one value is required`) when called with no arguments.
:::

:::member[public static function max(Decimal ...$values): self]
Returns the largest of the arguments, unchanged. When several are equal, the first one wins.

**Throws** `\InvalidArgumentException` (`At least one value is required`) when called with no arguments.
:::

:::member[public static function sum(Decimal ...$values): self]
Returns the total at the largest scale among the arguments. `Decimal::sum(\Tyhp\decimal('1.5'), \Tyhp\decimal('2.25'))` is `3.75`.

**Throws** `\InvalidArgumentException` (`At least one value is required`) when called with no arguments. For a list that can be empty, start from `Decimal::zero()` and use `+=` in a loop.
:::

:::member[public static function avg(Decimal ...$values): self]
Returns the arithmetic mean at the scale of the sum. The division keeps four extra digits, then the result is reduced to that scale with `withScale()`. Averaging `9.99`, `10`, and `2.50` gives `7.50`. When every input has scale 0, the result is rounded half up to a whole number (`avg(1, 2)` is `2`), so give the inputs the scale you want back.

**Throws** `\InvalidArgumentException` (`At least one value is required`) when called with no arguments.
:::

#### Backend management

:::member[public static function getBackendName(): string]
Returns the name of the active backend: `'decimal'`, `'bcmath'`, `'gmp'`, `'integer-scaled'`, or the `getName()` of a backend you installed with `setBackend()`. Calling it selects the backend if no operation has done so yet. Useful in health checks and diagnostics.
:::

:::member[public static function setBackend(\Tyhp\Backend\DecimalBackend $backend): void]
Replaces the backend for every `Decimal` operation in the current PHP process from now on. Use it in tests (for example, to run the suite against `IntegerScaledBackend`) or to wrap the default backend with instrumentation. Once set, automatic selection no longer runs.
:::

#### Operator methods

The compiler turns operators on `decimal` values into calls to these public static methods. They are part of the compiled-code contract. In Tyhp code, write the operator; in plain PHP, call the named methods.

In the table, `L` is `self|float|int|string` and `R` is `self|\Tyhp\DecimalCoercible`.

| Method | Used for |
|--------|----------|
| `__add(L $l, R $r): self` | `+` |
| `__subtract(L $l, R $r): self` | `-` |
| `__multiply(L $l, R $r): self` | `*` |
| `__divide(L $l, R $r): self` | `/` |
| `__mod(L $l, R $r): self` | `%` |
| `__pow(self $l, int $r): self` | `**` |
| `__negate(self $o): self` | unary `-` |
| `__isEqual(L $l, R $r): bool` | `==` |
| `__isNotEqual(L $l, R $r): bool` | `!=` |
| `__isLessThan(L $l, R $r): bool` | `<` |
| `__isLessThanOrEqual(L $l, R $r): bool` | `<=` |
| `__isGreaterThan(L $l, R $r): bool` | `>` |
| `__isGreaterThanOrEqual(L $l, R $r): bool` | `>=` |
| `__compare(L $l, R $r): int` | `<=>` |
| `__asNumeric(self $o): float` | unary `+` |
| `__from(int\|float\|string $from): self` | `(decimal)` casts, and the conversion of a scalar to a `decimal` parameter or return value |

A call to an arithmetic or comparison method needs a `Decimal` on at least one side. `Decimal::__add(1, 2)` throws `\Tyhp\Exceptions\InvalidParametersForOperatorOverloadException`.

### The `\Tyhp\DecimalCoercible` type alias

:::member[type DecimalCoercible = float|int|string|\Tyhp\Contracts\DecimalConvertible]
Everything that can be turned into a `Decimal`. Use it for parameters that accept "anything numeric" and convert on entry:

```tyhp
<?tyhp

use Tyhp\Decimal;

function money(\Tyhp\DecimalCoercible $value): decimal {
    return new Decimal($value, 2);
}

money('3.456');   // 3.46
money(12);        // 12.00
```

`\Tyhp\DecimalCoercible()` returns the alias as a runtime `\Tyhp\Type` (see [Type Aliases](tyhp_0700_typeAliases.md)).
:::

### `\Tyhp\Contracts\DecimalConvertible`

:::member[interface DecimalConvertible extends \Tyhp\Contracts\Convertible]
Implement this on your own value objects so they can be passed anywhere a `DecimalCoercible` is accepted: to `\Tyhp\decimal()`, the `Decimal` constructor, and every `Decimal` method that takes an operand (`add()`, `compareTo()`, and the others).

`public function __toDecimal(): \Tyhp\Decimal;` returns the decimal form of the object.

A `DecimalConvertible` object can be the right operand of a decimal operator: `$unit + $price` with `$unit` a `decimal` and `$price` a `Price`.

Declaring `operator convert(self $value): decimal` on a class also gives it `__toDecimal()` and the interface in the compiled PHP (see [Operator Overloads](tyhp_1600_operatorOverloads.md)), so such a class needs no `implements` clause to be used as an operand.

```tyhp
<?tyhp

use Tyhp\Decimal;

final class Price implements \Tyhp\Contracts\DecimalConvertible
{
    public function __construct(private readonly int $cents) {}

    public function __toDecimal(): Decimal {
        return (new Decimal($this->cents))->divide(100, 2);
    }
}

$price = new Price(1999);
decimal $unit = \Tyhp\decimal($price);                 // 19.99
decimal $sum = $unit + $price;                         // 39.98
```
:::

### `\Tyhp\Backend\DecimalBackend`

:::member[interface DecimalBackend]
The arithmetic engine behind `Decimal`. You only implement it to supply your own backend through `Decimal::setBackend()`. Every operand is a plain decimal string (`-?digits(.digits)?`), and `$scale` is the result scale. Return results truncated to exactly `$scale` fractional digits to match the built-in backends.

| Method | Contract |
|--------|----------|
| `add(string $a, string $b, int $scale): string` | `$a + $b` |
| `subtract(string $a, string $b, int $scale): string` | `$a - $b` |
| `multiply(string $a, string $b, int $scale): string` | `$a * $b` |
| `divide(string $a, string $b, int $scale): string` | `$a / $b`; throw `\DivisionByZeroError` when `$b` is zero |
| `modulo(string $a, string $b, int $scale): string` | Remainder with the sign of `$a`; throw `\DivisionByZeroError` when `$b` is zero |
| `power(string $base, int $exponent, int $scale): string` | `$base ** $exponent` for `$exponent >= 0` |
| `sqrt(string $value, int $scale): string` | Square root; throw `\InvalidArgumentException` when `$value` is negative |
| `compare(string $a, string $b, int $scale): -1\|0\|1` | Compare at `$scale` |
| `negate(string $value): string` | `-$value`; zero stays unsigned |
| `abs(string $value): string` | Absolute value |
| `getName(): string` | Name reported by `Decimal::getBackendName()` |

This backend wraps another one and changes only its name, which is a starting point for logging or metrics:

```tyhp
<?tyhp

use Tyhp\Decimal;
use Tyhp\Backend\DecimalBackend;
use Tyhp\Backend\IntegerScaledBackend;

final class LoggingBackend implements DecimalBackend
{
    public function __construct(private readonly DecimalBackend $inner) {}

    public function add(string $a, string $b, int $scale): string { return $this->inner->add($a, $b, $scale); }
    public function subtract(string $a, string $b, int $scale): string { return $this->inner->subtract($a, $b, $scale); }
    public function multiply(string $a, string $b, int $scale): string { return $this->inner->multiply($a, $b, $scale); }
    public function divide(string $a, string $b, int $scale): string { return $this->inner->divide($a, $b, $scale); }
    public function modulo(string $a, string $b, int $scale): string { return $this->inner->modulo($a, $b, $scale); }
    public function power(string $base, int $exponent, int $scale): string { return $this->inner->power($base, $exponent, $scale); }
    public function sqrt(string $value, int $scale): string { return $this->inner->sqrt($value, $scale); }
    public function compare(string $a, string $b, int $scale): -1|0|1 { return $this->inner->compare($a, $b, $scale); }
    public function negate(string $value): string { return $this->inner->negate($value); }
    public function abs(string $value): string { return $this->inner->abs($value); }
    public function getName(): string { return 'logging(' . $this->inner->getName() . ')'; }
}

Decimal::setBackend(new LoggingBackend(new IntegerScaledBackend()));
echo Decimal::getBackendName();   // logging(integer-scaled)
```
:::

### `\Tyhp\Backend\IntegerScaledBackend`

:::member[final class IntegerScaledBackend implements DecimalBackend]
The pure-PHP backend. It needs no extension and is selected automatically when `ext-decimal`, `ext-bcmath`, and `ext-gmp` are all missing. It is noticeably slower than the extension backends.

`public function __construct()` raises this `E_USER_NOTICE` the first time an instance is created in a process:

```text
Tyhp\Decimal: Neither ext-decimal, ext-bcmath, nor ext-gmp is loaded. Using pure-PHP integer-scaled fallback, which is slower and has precision limitations. Install ext-decimal (preferred) or ext-bcmath for optimal performance: https://php-decimal.github.io/ or https://www.php.net/manual/en/book.bc.php
```

`getName()` returns `'integer-scaled'`. Construct it yourself and pass it to `Decimal::setBackend()` to check that your code gives the same results without any extension.
:::

## Backends

The backend is chosen once per PHP process, the first time a decimal operation (or `Decimal::getBackendName()`) runs, and then reused. The choice is made at runtime with `\extension_loaded()` checks in this order:

1. `ext-decimal` → `decimal`
2. `ext-bcmath` → `bcmath`
3. `ext-gmp` → `gmp`
4. Otherwise → `integer-scaled`, with the one-time notice shown above

All backends follow the same scale and truncation rules, so results do not depend on which extension is loaded. Install `ext-bcmath` or `ext-decimal` on production servers; they are the fastest and most widely used. To confirm which backend a server uses, log `Decimal::getBackendName()` at startup.

:::note
The backend is picked at runtime from the extensions that are loaded. To force a specific one, for example in tests, call `Decimal::setBackend()`.
:::

The `tyhpdef/php-ext-decimal` package (type definitions for the PECL Decimal extension's own `\Decimal\Decimal` class) is unrelated to this package. You do not need it to use `\Tyhp\Decimal`, even when `ext-decimal` is the active backend.

## Errors

| Situation | Thrown | Message |
|-----------|--------|---------|
| A string the parser rejects | `\InvalidArgumentException` | `Cannot create Decimal from non-numeric string: {input}` |
| A `NaN` or `INF` float | `\InvalidArgumentException` | `Cannot create Decimal from NaN or Inf float value` |
| `divide()` / `/` by zero | `\DivisionByZeroError` | `Cannot divide {value} by zero` |
| `modulo()` / `%` by zero | `\DivisionByZeroError` | `Modulo by zero` |
| A negative `$scale` (`withScale()`, the constructor) | `\ValueError` | `Decimal scale must be 0 or greater, {scale} given` |
| A negative `$precision` (`round()`, and `format()` with a negative `$decimals`) | `\ValueError` | `Rounding precision must be 0 or greater, {precision} given` |
| `power()` with a negative exponent | `\InvalidArgumentException` | `Negative exponents are not supported` |
| `sqrt()` of a negative value | `\InvalidArgumentException` | `Square root of a negative number is not supported` |
| `min()`, `max()`, `sum()`, `avg()` with no arguments | `\InvalidArgumentException` | `At least one value is required` |

`\DivisionByZeroError` extends `\ArithmeticError`, which is an `\Error`. A `catch (\Exception $e)` block does not catch it; catch `\DivisionByZeroError` or `\Throwable`.

## Recipes

### Invoice totals with tax

Keep line amounts at two places, widen before applying a tax rate, and round each line's tax once.

```tyhp
<?tyhp

use Tyhp\Decimal;

final class InvoiceLine
{
    public function __construct(
        public readonly string $description,
        public readonly decimal $unitPrice,
        public readonly int $quantity,
    ) {}

    public function net(): decimal {
        return $this->unitPrice * $this->quantity;
    }

    public function tax(decimal $rate): decimal {
        return ($this->net()->withScale(6) * $rate)->round(2);
    }
}

final class Invoice
{
    private array<int, InvoiceLine> $lines = [];

    public function __construct(private readonly decimal $taxRate) {}

    public function add(InvoiceLine $line): void {
        $this->lines[] = $line;
    }

    public function netTotal(): decimal {
        decimal $sum = Decimal::zero(2);
        foreach ($this->lines as InvoiceLine $line) {
            $sum += $line->net();
        }
        return $sum;
    }

    public function taxTotal(): decimal {
        decimal $sum = Decimal::zero(2);
        foreach ($this->lines as InvoiceLine $line) {
            $sum += $line->tax($this->taxRate);
        }
        return $sum;
    }

    public function grandTotal(): decimal {
        return $this->netTotal() + $this->taxTotal();
    }
}

$invoice = new Invoice(\Tyhp\decimal('0.0825'));
$invoice->add(new InvoiceLine('Widget', \Tyhp\decimal('19.99'), 3));
$invoice->add(new InvoiceLine('Gadget', \Tyhp\decimal('4.25'), 2));

echo $invoice->netTotal()->format(), "\n";    // 68.47
echo $invoice->taxTotal()->format(), "\n";    // 5.65
echo $invoice->grandTotal()->format(), "\n";  // 74.12
```

Some tax rules round the invoice total instead of each line. In that case, sum the unrounded line taxes (`$this->net()->withScale(6) * $rate`) and call `round(2)` once on the sum.

### Splitting an amount without losing cents

Dividing `100.00` three ways gives `33.33` three times, which loses a cent. Compute the truncated share, then give the remainder to the first part:

```tyhp
<?tyhp

function allocate(decimal $total, int $parts): array<int, decimal> {
    if ($parts < 1) {
        throw new \InvalidArgumentException('parts must be at least 1');
    }

    decimal $amount = $total->withScale(2);
    decimal $share = $amount->divide($parts, 2);
    decimal $remainder = $amount - $share * $parts;

    array<int, decimal> $shares = [];
    for (int $i = 0; $i < $parts; $i++) {
        $shares[] = $share;
    }
    $shares[0] = $shares[0] + $remainder;

    return $shares;
}

foreach (allocate(\Tyhp\decimal('100.00'), 3) as decimal $share) {
    echo $share, "\n";   // 33.34, 33.33, 33.33
}
```

### Parsing user input

The constructor accepts only plain digits with an optional `-` and `.`. Remove formatting first, and check the shape so you can show a helpful error instead of letting the exception escape:

```tyhp
<?tyhp

use Tyhp\Decimal;

function parseAmount(string $input): ?decimal {
    string $normalized = \str_replace([',', ' '], '', \trim($input));
    if (\preg_match('/^-?\d+(\.\d{1,2})?$/', $normalized) !== 1) {
        return null;
    }
    return new Decimal($normalized, 2);
}

$amount = parseAmount(' 1,234.50 ');
echo $amount === null ? 'invalid' : $amount->value;   // 1234.50
```

This version treats `,` as a thousands separator. For locales that use `,` as the decimal separator, convert it to `.` instead. When you would rather let the constructor validate, catch its exception:

```tyhp
<?tyhp

use Tyhp\Decimal;

function parseOrThrow(string $input): decimal {
    try {
        return new Decimal($input);
    } catch (\InvalidArgumentException $e) {
        throw new \DomainException("Not a valid amount: {$input}", 0, $e);
    }
}
```

### Storing decimals in a database

Use a fixed-point column (`DECIMAL(12,2)` in MySQL, `NUMERIC(12,2)` in PostgreSQL) and pass `value` as a string. PDO returns these columns as strings, which you can pass straight to the constructor.

```tyhp
<?tyhp

use Tyhp\Decimal;

final class PaymentRepository
{
    public function __construct(private readonly \PDO $pdo) {}

    public function record(int $orderId, decimal $amount): void {
        $stmt = $this->pdo->prepare('INSERT INTO payments (order_id, amount) VALUES (:order_id, :amount)');
        $stmt->execute([
            'order_id' => $orderId,
            'amount' => $amount->withScale(2)->value,
        ]);
    }

    public function totalFor(int $orderId): decimal {
        $stmt = $this->pdo->prepare('SELECT COALESCE(SUM(amount), 0) FROM payments WHERE order_id = :order_id');
        $stmt->execute(['order_id' => $orderId]);
        $raw = $stmt->fetchColumn();
        if (!\is_string($raw) && !\is_int($raw)) {
            throw new \UnexpectedValueException('Unexpected SUM(amount) result');
        }
        return new Decimal($raw, 2);
    }
}
```

Do not store decimals in `FLOAT` or `DOUBLE` columns, and do not read them back through `(float)`. Either step reintroduces binary rounding error.

### JSON APIs

`\json_encode()` writes a `Decimal` as a JSON string, so no digits are lost on the way out. Ask clients to send amounts as strings too; a JSON number is decoded as a PHP `float` before your code sees it.

```tyhp
<?tyhp

use Tyhp\Decimal;

function amountFromJson(array<int|string, mixed> $payload): decimal {
    $raw = $payload['amount'] ?? null;
    if (!\is_string($raw)) {
        throw new \InvalidArgumentException('amount must be a JSON string such as "19.99"');
    }
    return new Decimal($raw, 2);
}

$payload = \json_decode('{"amount": "19.99"}', true, 512, \JSON_THROW_ON_ERROR);
if (!\is_array($payload)) {
    throw new \UnexpectedValueException('Expected a JSON object');
}
decimal $amount = amountFromJson($payload);
echo \json_encode(['amount' => $amount, 'doubled' => $amount * 2], \JSON_THROW_ON_ERROR);
// {"amount":"19.99","doubled":"39.98"}
```

### Sorting and aggregating

```tyhp
<?tyhp

use Tyhp\Decimal;

array<int, decimal> $prices = [\Tyhp\decimal('9.99'), \Tyhp\decimal('10'), \Tyhp\decimal('2.50')];

\usort($prices, fn(Decimal $a, Decimal $b): int => $a <=> $b);

decimal $cheapest = Decimal::min(...$prices);   // 2.50
decimal $average = Decimal::avg(...$prices);    // 7.50
```

To use decimals as array keys (for example, to group by price), use a normalized string such as `$price->withScale(2)->value`. `'5.0'` and `'5.00'` are different keys.

## Using `\Tyhp\Decimal` from plain PHP

The class is ordinary PHP once compiled, so hand-written PHP in the same project can use it through its methods. PHP has no operator overloading: `$a + $b` on two `Decimal` objects throws `\TypeError` (`Unsupported operand types`), and PHP's `==` and `<` compare the object properties, so `5.0 == 5.00` is `false`. Call the methods instead.

```php
<?php

declare(strict_types=1);

use Tyhp\Decimal;

$total = \Tyhp\decimal('19.99')->multiply(3)->add('4.50');

echo $total->format(2), "\n";                       // 64.47
echo $total->equals('64.470') ? 'equal' : 'different', "\n"; // equal

try {
    $share = $total->divide(0);
} catch (\Throwable $e) {
    echo $e->getMessage(), "\n";                    // Cannot divide 64.47 by zero
}
```

## Gotchas

- **Integer division stays whole.** `10 / 3` on decimals with scale 0 is `3`. Call `divide($x, $scale)`, or give an operand the scale you want.
- **Results truncate.** `*`, `/`, `**`, and `sqrt()` drop digits beyond the result scale. Widen with `withScale()` first and `round()` at the end.
- **Floats are not exact.** `new Decimal(0.1)` is `0.10000000000000000555`, and `$a + 0.01` adds `0.01000000000000000021`. Construct from strings and write string operands.
- **Do not use `===` on decimals.** It compares object identity. Use `==`.
- **`withScale()` and the constructor truncate** unless `roundingMode` is `\PHP_ROUND_HALF_UP`. Use `round($precision, $mode)` to pick a rounding mode explicitly.
- **Scale is part of the string.** `'5.0'` and `'5.00'` are equal numbers but different `value` strings. Normalize with `withScale()` before using `value` as a key or comparing strings.
- **Leading zeros survive.** `new Decimal('007.50')` prints as `007.50`. Normalize input before constructing (`$value + 0` also normalizes it to `7.50`).
- **`\DivisionByZeroError` is not an `\Exception`.** Catch it explicitly or catch `\Throwable`.

## Related pages

- [New and Changed Types](tyhp_0150_newTypes.md) — the `decimal` type and how it compiles.
- [Operator Overloads](tyhp_1600_operatorOverloads.md) — how operator declarations and `convert` work.
- [PHP Version Gating](tyhp_0320_phpVersionGating.md) — the `declare(ext=…)` checks that select the backend.
- [Runtime Packages Overview](package_intro.md) — all `tyhp/*` packages.
- [The tyhp/core Package](package_core.md) — the `Convertible` contracts that `Decimal` implements.
- [Composer Runtime Packages](project_composerPackages.md) — versioning and installation.
