---
name: cstk-image-generation
description: "Image prompt enhancement (Subject-Context-Style) for illustrations, photos, visual assets, edits. Triggers: \"image prompt\", \"illustration\", \"mockup image\", \"generate a picture\". Skip for technical diagrams (Mermaid/PlantUML/drawio)."
---

# CSTK Adaptation

Adapted from `JotJunior/cstk` skill `image-generation` at commit `35922cf`.
Use this as a Codex skill; follow local repository instructions and Codex tool names when source text mentions Claude-specific commands or slash commands.

# Image Generation Prompt Best Practices

## Prompt Structure

Enhance every image generation prompt around three core elements:

### 1. SUBJECT (What)

The main focus of the image.

- Physical characteristics: textures, materials, colors, scale
- Actions, poses, expressions if applicable
- Distinctive features that define the subject

### 2. CONTEXT (Where/When)

The environment and conditions.

- Setting, background, spatial relationships (foreground, midground, background)
- Time of day, weather, atmospheric conditions
- Mood and emotional tone of the scene

### 3. STYLE (How)

The visual treatment.

- Artistic or photographic approach: reference specific artists, movements, or styles
- Lighting design: direction, quality, color temperature, shadows
- Camera/lens choices: specify focal length, aperture, and shooting angle when photographic

## Core Principles

- **Preserve intent** — Enrich the user's original vision, never override it
- **Positive descriptions only** — Describe what should be present; rephrase any exclusion as an inclusion
- **Specific over vague** — "golden hour sunlight at 15° angle" beats "nice lighting"
- **Natural flow** — Weave elements into a single flowing description, not a bullet list

## Enhancement Patterns

### Hyper-Specific Details

Add concrete visual details where the user left gaps:

- Lighting → direction, quality, color temperature, shadow behavior
- Textures → surface materials, weathering, reflectivity
- Atmosphere → particulates, humidity, depth haze
- Scale → relative sizes, distances, proportions

### Camera Control Terminology

When a photographic look is appropriate:

- Lens type: "shot with 85mm portrait lens", "wide-angle 24mm"
- Aperture: "shallow depth of field at f/1.8", "deep focus at f/11"
- Angle: "low angle emphasizing height", "bird's eye view"
- Motion: "motion blur on the paws", "frozen mid-action"

### Atmospheric Enhancement

Convey mood through environmental details:

- Emotional tone: "serene", "ominous", "jubilant"
- Light quality: "dappled shadows", "harsh midday sun", "soft diffused overcast"
- Weather/air: "morning mist", "dust particles in a sunbeam"

### Text in Images

When the image should contain readable text (signs, labels, titles, typography):

- Specify the exact text content in quotes: `"OPEN 24 HOURS" in bold sans-serif`
- Describe visual treatment: font style, weight, size relative to the scene
- Define placement and integration: "centered on the storefront awning", "hand-lettered on the chalkboard"

## Feature Patterns

### Character Consistency

When the same character must be recognizable across multiple images:

- Include **at least 3 recognizable visual markers** (distinctive scar, signature clothing, unique hairstyle, characteristic accessory)
- Use anchoring words: "distinctive", "signature", "always wears", "always has"
- Be specific: "round tortoiseshell glasses" not just "glasses"

### Compositional Integration (Multi-Element Blending)

When combining multiple visual elements in one scene:

- Define spatial relationships with proportions: "foreground (40% of frame)", "midground", "background"
- Use integration language: "seamlessly blending", "harmoniously composed", "naturally integrated"
- Specify relative scale and interaction between elements

### Real-World Accuracy

When depicting real places, cultures, or historical elements:

- Use specific terminology: "traditional Edo-period architecture", "authentic Moroccan zellige tilework"
- Include culturally accurate details
- Reference geographical or historical specifics

### Purpose-Driven Enhancement

Tailor the prompt to the intended use:

| Purpose | Emphasis |
|---------|----------|
| Product photo | Clean background, studio lighting, commercial appeal |
| UI mockup | Flat design elements, consistent spacing, screen-appropriate |
| Presentation slide | Bold composition, clear focal point, text-friendly layout |
| Social media | Eye-catching, vibrant, crop-friendly aspect ratio |
| Book/album cover | Typography space, dramatic mood, symbolic elements |

## Image Editing

When modifying an existing image:

- **Preserve** the original's core characteristics: color palette, lighting style, composition
- Use anchoring phrases: "maintain the existing...", "preserve the original...", "keep the same..."
- Be specific about what to change vs what to keep unchanged
- Describe modifications relative to the existing image, not from scratch

## Example

**Input:** "A happy dog in a park"

**Enhanced:** "Golden retriever mid-leap catching a red frisbee, ears flying, tongue out in joy, in a sunlit urban park. Soft morning light filtering through oak trees creates dappled shadows on emerald grass. Background shows families on picnic blankets, slightly out of focus. Shot from low angle emphasizing the dog's athletic movement, with motion blur on the paws suggesting speed."

---

## Gotchas

### Positive descriptions only — exclusions become inclusions

"No clouds" becomes "clear blue sky". "Not blurry" becomes "sharp focus, crisp detail". Image models attend to what is written, not what is excluded. Every negative phrasing is a prompt bug.

### Specific beats vague, always

"Nice lighting" gives the model nothing to anchor on. "Golden hour sunlight at 15° angle, long soft shadows, warm amber color temperature" produces consistent output. Vague prompts produce generic results.

### Preserve user intent — enrich, don't override

If the user says "cozy coffee shop", don't swap it for "modern minimalist cafe" because that's trendier. Enhance the original vision with concrete details that serve THEIR concept.

### Character consistency needs 3+ recognizable markers

A single "tall woman with brown hair" won't survive across images. You need "distinctive scar above left eyebrow, signature red scarf, always wears round tortoiseshell glasses" — three anchors minimum.

### Image editing: anchor what stays before describing what changes

"Change the sky to sunset" risks the model regenerating the whole image. "Maintain the original composition, color palette of the foreground, and architectural details — only change the sky to a vivid sunset" preserves what matters.

### Text in images needs quoted content, font, placement

Image models hallucinate text by default. If the image should contain readable text, specify: `"OPEN 24 HOURS" in bold sans-serif, centered on the storefront awning`. Without those anchors, expect garbled text.

## Source License

This skill includes material adapted from `JotJunior/cstk`, licensed under MIT. The copyright and permission notice are included in `references/cstk-license.md`.

