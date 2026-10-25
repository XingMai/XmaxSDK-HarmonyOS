# SDK Documentation Conventions

These conventions apply to SDK-owned ArkTS, C++, and native interface declarations. They do not apply to example apps, generated files, or third-party code.

## File Headers

Use the actual filename and the following header. Keep the repository URL in `GitHub:` rather than adding a separate `Repo:` field or linking to an author's profile.

```text
//
//  MediaService.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//
```

## Types and Members

- Write source comments in English, preserving localized runtime strings and the prescribed author name.
- Document every type, method, constructor, accessor, property, enum case, and standalone function, including private declarations.
- Describe types by their responsibility, methods by their result, and properties by their meaning.
- Use `/** ... */` for declaration documentation and `//` for implementation explanations. A short declaration description may use a single-line documentation comment.
- Keep related members together. Do not use documentation comments as section headings or add headings for small groups.
- Describe units, ranges, defaults, ownership, and missing values when they affect correct use. State shared conventions once and document exceptions separately.

## Methods and Callbacks

- Lead with a concise summary, followed by essential behavior, parameter descriptions, return values, and synchronous errors, in that order. Separate these sections with an empty documentation line.
- Match parameter names and order to the declaration. Omit descriptions that merely repeat types or documented properties assigned by a constructor.
- Omit return-value documentation when the summary is sufficient. Do not add it to constructors or `void` methods.
- For `Promise<void>`, explain meaningful fulfillment timing in the behavior section. Distinguish Promise rejection from synchronous exceptions and runtime listener notifications.
- Document lifecycle requirements, cancellation, late results, callback delivery, buffer validity, and resource release when they affect callers or essential maintenance.
- Keep shared contracts on interfaces. Implementations need concise descriptions and implementation-specific constraints, not copies of the entire interface contract.

```typescript
/**
 * Sets the video statistics listener for the current generation stream.
 *
 * The listener receives undefined when the result stream is cleared.
 *
 * @param listener The statistics handler, or null to remove it.
 */
setDownlinkVideoStatisticsListener(
  listener: DownlinkVideoStatisticsListener | null
): void;
```

## Formatting and Review

- Use two-space ArkTS indentation and one blank line between declarations. Put each declaration parameter on its own line, including a single parameter.
- Separate distinct logical steps inside methods, functions, and callbacks with one blank line. Keep each step's statements together.
- Make phase changes visible, such as validation, resource creation, callback binding, execution, state commitment, notification, and cleanup. Choose boundaries by responsibility, not a fixed line count.
- Keep declarations with the conditions that initialize or validate them, and keep related calculations and assignments together. Do not add a blank line after every statement or control-flow block, or extract helpers solely to create visual sections.
- Expand multi-argument calls, except compact scalar expressions or string interpolations where expansion would harm readability.
- Preserve ArkUI component structure, decorator order, Surface lifecycle, and modifier execution order.
- Use two-space C++ block indentation and four-space continuation indentation.
- Avoid boilerplate, implementation history, debugging observations, and claims of alignment with another platform.
- Verify descriptions against the implementation. Formatting-only changes must preserve executable code, API signatures, defaults, parameter order, access control, and ownership.
- Review method bodies as well as declarations: parameter wrapping alone does not satisfy the formatting conventions. Apply the same logical grouping to native implementations.
