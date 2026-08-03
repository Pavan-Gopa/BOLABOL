---
type: "query"
date: "2026-08-01T08:54:50.444576+00:00"
question: "Поставить SF Pro Rounded в заголовок Blaboom вместо Comic Sans"
contributor: "graphify"
outcome: "useful"
source_nodes: ["BlaboomTitleWordmarkView", "ReleaseIdentityTests.swift"]
---

# Q: Поставить SF Pro Rounded в заголовок Blaboom вместо Comic Sans

## Answer

Expanded from original query via graph vocab: [comic, font, system, title, wordmark]. BlaboomTitleWordmarkView now renders BLABOOM! with Font.system(size: 16, weight: .bold, design: .rounded). Comic Sans lookup and custom font branch were removed. ReleaseIdentityTests asserts the rounded system font and rejects ComicSans/custom font usage. swift test --arch arm64 passed, fresh dist/Blaboom.app built, signed, launched, and visually verified.

## Outcome

- Signal: useful

## Source Nodes

- BlaboomTitleWordmarkView
- ReleaseIdentityTests.swift