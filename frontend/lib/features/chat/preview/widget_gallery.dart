import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/widget_structure.dart';
import '../../../core/theme/app_palette.dart';
import '../widgets/markdown/app_markdown.dart';

/// One reply that exercises every drawable block the model can emit. Also
/// the fixture for the gallery widget test.
const kWidgetGallerySample = '''
## Structure widgets

```stats
title: Q3 snapshot
stat: Revenue | 1.2M | +12% | up
stat: Churn | 3.1% | -0.4% | down
spark: Revenue | 3,4,4,6,7,9
```

```chart
{"type":"bar","title":"Monthly sales","x":["Jan","Feb","Mar"],"series":[{"name":"2025","data":[12,18,15]},{"name":"2026","data":[14,22,25]}],"unit":"k USD"}
```

```chart
{"type":"donut","title":"Share","slices":[{"name":"A","value":50},{"name":"B","value":30},{"name":"C","value":20}]}
```

```progress
title: Skills
bar: Dart | 80 | 100 | daily driver
bar: Rust | 3 | 10
rating: Docs | 4 | 5
```

```compare
title: Databases
option: Postgres | relational, extensible | pick
+ Rich types and extensions
+ Strong consistency
- Heavier to operate
option: MongoDB | document store
+ Flexible schema
- Weaker joins
```

```tree
title: Flutter
Flutter
  Widgets
    Stateless
    Stateful
  Rendering
    RenderObject
  Engine
```

```timeline
title: History of the web
1991 | First website | Tim Berners-Lee publishes it at CERN
1995 | JavaScript | Created in 10 days
```

```flow
title: Pipeline
box: Ingest | Collect events
box: Serve | Low latency | accent
```

| Language | Stars (k) | Typed |
| --- | --- | --- |
| Dart | 40 | yes |
| Python | 120 | no |
| Rust | 95 | yes |

Euler: \$\$e^{i\\pi} + 1 = 0\$\$

```compare
this is not valid
```
''';

/// Debug screen: renders [kWidgetGallerySample] through the real markdown
/// pipeline, so light/dark and bad-input fallbacks can be eyeballed.
class WidgetGalleryScreen extends StatelessWidget {
  const WidgetGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        title: const Text(StructStrings.galleryTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: const [
          AppMarkdown(
            data: kWidgetGallerySample,
            citations: [],
            streaming: false,
          ),
        ],
      ),
    );
  }
}
