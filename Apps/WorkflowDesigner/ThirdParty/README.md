# Vendored third-party code

## DMTabBar

`DMTabBar/` is an Xcode-style icon tab bar by Daniele Margutti, 2012,
<http://www.danielemargutti.com>, under the **MIT licence**. The copyright and
licence notices in each file are the author's and stay as they are. MIT
allows it to ship inside an LGPL work, so WorkflowDesigner ships it under
WorkflowKit's licence while those notices remain.

It is copied from RDLKit's RDLDesigner, which took it from the XForms
Designer. That copy is already adapted for GNUstep and for dark appearances:

* It imports `<AppKit/AppKit.h>` rather than `<Cocoa/Cocoa.h>`, which
  GNUstep doesn't have.
* `-setDefaults` takes the bar's gradient from `windowBackgroundColor`, so
  the bar follows the theme.

The bar draws icons. WorkflowDesigner draws them with `WKDTabBadge`, a port
of RDLKit's `RDLTabBadge`, rather than shipping images.
