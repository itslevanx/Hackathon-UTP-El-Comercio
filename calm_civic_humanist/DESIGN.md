---
name: Calm Civic Humanist
colors:
  surface: '#edfdf3'
  surface-dim: '#cdded4'
  surface-bright: '#edfdf3'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#e7f8ee'
  surface-container: '#e1f2e8'
  surface-container-high: '#dcece2'
  surface-container-highest: '#d6e6dd'
  on-surface: '#101e19'
  on-surface-variant: '#414845'
  inverse-surface: '#25332d'
  inverse-on-surface: '#e4f5eb'
  outline: '#717975'
  outline-variant: '#c1c8c4'
  surface-tint: '#416659'
  primary: '#00271d'
  on-primary: '#ffffff'
  primary-container: '#183d32'
  on-primary-container: '#81a899'
  inverse-primary: '#a8cfc0'
  secondary: '#106c4c'
  on-secondary: '#ffffff'
  secondary-container: '#9ff1c8'
  on-secondary-container: '#187050'
  tertiary: '#002439'
  on-tertiary: '#ffffff'
  tertiary-container: '#003a59'
  on-tertiary-container: '#71a5cf'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#c3ebdb'
  primary-fixed-dim: '#a8cfc0'
  on-primary-fixed: '#002118'
  on-primary-fixed-variant: '#294d42'
  secondary-fixed: '#a1f3cb'
  secondary-fixed-dim: '#86d7b0'
  on-secondary-fixed: '#002114'
  on-secondary-fixed-variant: '#005137'
  tertiary-fixed: '#cbe6ff'
  tertiary-fixed-dim: '#98ccf8'
  on-tertiary-fixed: '#001e30'
  on-tertiary-fixed-variant: '#064b70'
  background: '#edfdf3'
  on-background: '#101e19'
  surface-variant: '#d6e6dd'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-lg:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-sm:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-xl:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '400'
    lineHeight: 32px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '500'
    lineHeight: 28px
  label-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  label-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 24px
  label-sm:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 22px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.5rem
  space-sm: 0.75rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system establishes a peaceful, dignified, and ultra-legible civic interface crafted specifically for multi-generational communities and older adults (such as Rosa, 72). The interface discards fleeting digital noise—eliminating decorative gradients, ambiguous iconography, and microscopic utility typography—in favor of high-contrast clarity, calm spatial rhythm, and explicit intent.

### Core Philosophy
- **Unambiguous Predictability:** Every interactable element looks physical, accessible, and self-explanatory. Iconography is strictly accompanied by clear Spanish text labels (e.g., "← Volver" instead of solitary arrows).
- **Generous Physical Touch Targets:** Designed for varying degrees of motor control and eyesight; primary touch areas meet or exceed 48px to 56px heights.
- **Calm Civic Dignity:** Grounded in deep architectural forest greens and crisp bone-white surfaces that convey civic responsibility, safety, and community trust without feeling cold or bureaucratic.

## Colors

The color palette is architected for strict WCAG AAA contrast compliance against light canvases, avoiding visually fatiguing ultra-saturated tones.

### Color Roles
- **Primary Forest Dark (`#183D32`):** Primary branding, top headers, institutional status anchors, and heavy typography markers.
- **Action Primary Green (`#267A59`):** Interactive CTA surfaces, primary buttons, active toggles, and confirmed states.
- **Soft Green Background Tint (`#E9F3EC`):** Highlight surfaces, secondary callout banners, and verified community badge fills.
- **Main Canvas Background (`#F8F9F6`):** The soothing, non-glare off-white background of the application.
- **Card Surface (`#FFFFFF`):** High-clarity elevated surfaces for modular civic content.
- **Deep Text Primary (`#192721`):** Maximum contrast reading text (achieving > 12:1 contrast ratio against card surfaces).
- **Secondary Text (`#59675F`):** Supporting metadata, timestamps, and secondary instruction text (maintains > 4.5:1 ratio).
- **Structural Borders (`#DEE6DF`):** High-definition division borders defining cards and input boundaries without visual clutter.
- **Urgent / Emergency Red (`#B74E3D`):** Reserved solely for critical neighborhood alerts, security notices, and destructive confirmations.
- **Training / Practice Blue (`#366C93`):** Guided walk-throughs, educational neighbor tips, and civic assistance tools.

## Typography

Typography prioritizes rapid readability and legibility for aging eyes. Text below 16px is prohibited across all screens and components.

- **Baseline Body Size:** The default reading size is strictly 18px with relaxed line heights (`1.55` or 28px) to reduce line-jumping eye fatigue.
- **Font Pairing:** `Inter` is utilized throughout due to its tall x-height, clear optical counters, and unambiguous glyph distinctions (e.g., differentiating `1`, `l`, and `I`).
- **Pacing & Scannability:** Headlines rely on bold weights (700) with compact, snug line heights to anchor sections firmly without breaking sentence cadence.

## Layout & Spacing

A strict 8pt spatial grid system governs all margins, padding, and block flows. The layout is optimized mobile-first for single-handed usage on smartphones, scaling cleanly to tablet and desktop screens through a centralized reading column.

### Grid & Margins
- **Mobile (< 640px):** Single-column layout with fixed outer canvas margins of 16px (`1rem`) and vertical spacing rhythms of 16px to 24px between content modules.
- **Tablet / Desktop (≥ 640px):** Centered civic viewport constrained to a max-width of 540px for focused administrative tasks, or up to 840px for dual-pane community boards, maintaining generous negative space to reduce cognitive overload.
- **Bottom Navigation Clearance:** All scrolling views provide 96px of bottom content offset to prevent persistent navigation bars from obscuring critical inputs or buttons.

## Elevation & Depth

This design system avoids blurry pseudo-realistic dropshadows in favor of structural clarity, high-contrast outlines, and quiet tonal layering.

- **Surface Tiers:** Content modules sit on clean pure-white (`#FFFFFF`) card planes positioned against the softer canvas (`#F8F9F6`).
- **High-Definition Outlines:** Cards and interactive containers use a continuous 1.5px solid border in `#DEE6DF`. This ensures definite boundaries regardless of screen brightness, sunlight, or display contrast variance.
- **Elevated Interactive Layer:** Floating modals or floating alerts use a subtle 1px border combined with a soft, diffused ambient contact shadow (`0 4px 16px rgba(25, 39, 33, 0.08)`), ensuring clear separation without visual intimidation.

## Shapes

The design uses balanced, rounded geometries (level 2) that feel approachable and welcoming without appearing childish or overly stylized.

- **Primary Cards & Modals:** 16px (`rounded-lg`) corner radii for comfortable structural framing.
- **Interactive Buttons & Inputs:** 12px to 16px corner radii to communicate physical clickability.
- **Chips, Pills & Badges:** Fully rounded capsule curves (`rounded-full`) to immediately differentiate categorical tags and statuses from actionable rectangular cards.

## Components

### Buttons & Navigation Triggers
- **Primary Actions:** Minimum height of 56px with a solid `#267A59` background, white label text (`18px` weight 600), and full-width mobile availability. No subtle text links for critical flows.
- **Secondary Actions:** 56px height, background in `#E9F3EC`, text in `#183D32`, and a 1.5px border in `#267A59`.
- **Navigation Return ("← Volver"):** Prominent 48px height touch target positioned top-left, featuring a bold arrow alongside explicit text reading "← Volver" in `#183D32` at 18px medium weight.

### Cards & Neighborhood Modules
- Flat white containers with 16px internal padding, framed with 1.5px border (`#DEE6DF`).
- Content divided into clear optical chunks: Category Tag → Bold Title (20px) → Body Description (18px) → Single Action Target.

### Form Inputs & Text Fields
- Large 56px input heights with 18px text size.
- 2px prominent borders when focused (`#267A59`), paired with a pale tint focus glow (`#E9F3EC`).
- Persistent top-aligned field labels in `#192721` (never floating or disappearing placeholder-only hints) to safeguard against memory lapses during input.

### Selection Controls (Checkboxes & Radios)
- Oversized target areas: minimum 28px visual indicator inside a 52px tappable touch container.
- High-contrast states: checked indicators feature solid `#267A59` fill with a thick, crisp white checkmark (3px stroke).

### Chips & Status Badges
- **Status Badges:** Solid fill pills with 8px vertical and 16px horizontal padding.
  - *Normal/Notice:* `#E9F3EC` background with `#183D32` text.
  - *Urgent/Emergency:* `#FBEBE8` background with `#B74E3D` text.
  - *Tutorial/Help:* `#E7F0F6` background with `#366C93` text.

### Persistent Civic Bottom Navigation
- Fixed 72px height footer bar in `#FFFFFF` with a top structural border (`#DEE6DF`).
- 3 to 4 major community destinations only.
- Each destination contains a 28px clear outline/filled icon stacked with an explicit 16px text label. Unselected items sit at `#59675F`; active items are emphasized in `#267A59` with a subtle indicator pill.