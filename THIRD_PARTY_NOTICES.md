# Third-party notices: Redactor

Redactor's source is MIT (see [`LICENSE`](LICENSE)), and that license covers
this repository only. Everything listed below carries its own terms.

## Desert Ant Labs models and SDKs

Licensed under the **Desert Ant Labs Source-Available License, Version 1.0**.
Authoritative terms: **<https://license.desertant.com/1.0>** (machine-readable at
<https://license.desertant.com/1.0.txt>). Copyright © 2026 Desert Ant Labs B.V.
`SPDX-License-Identifier: LicenseRef-DAL-Source-Available-1.0`

In short: free below **100,000 monthly active devices per platform, per model**;
above that a commercial license is required (<licensing@desertant.com>). You may
embed the models in your application. You may **not** use the models, their
outputs, or their logs to train a competing on-device model. Apps that ship them
must credit Desert Ant Labs (<https://license.desertant.com/attribution>).

| Package | What it does here |
|---|---|
| [`desert-ant-core`](https://github.com/Desert-Ant-Labs/desert-ant-core) | `Redact` finds the personal data in what you copy |

The package bundles no weights. Redact downloads from Hugging Face on first
launch and carries its own third-party notices for the upstream weights it was
fine-tuned from.

## Desert Ant Labs brand kit

[`desert-ant-swift`](https://github.com/Desert-Ant-Labs/desert-ant-swift)
(product `DesertAntUI`) supplies the brand colors. The code is MIT. The Desert
Ant Labs name and mark are trademarks, and no license here grants rights to
them.

The Redact photo in Settings (`App/Assets.xcassets/RedactPhoto.imageset`) is
from the Redact model page and is not covered by the MIT license.

## Linked Swift packages

| Package | License | Copyright |
|---|---|---|
| [swift-numerics](https://github.com/apple/swift-numerics) | Apache-2.0 | Apple Inc. |

swift-numerics arrives through `Redact` and is listed because it ships in the
app.
