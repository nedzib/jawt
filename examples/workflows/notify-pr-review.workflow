workflow:
  name: notify-pr-review
  description: "Notifica los PR donde soy revisor directo"

  schedule:
    every: 10m

  nodes:
    start: { type: start }
    prs:
      type: pr-review
    notify:
      type: notify
      title: "jawt - notify-pr-review"
      message: "Tienes ${prs.count} PR(s) para revisar"
    end: { type: end }

  edges:
    - from: start.out
      to: prs.in
    - from: prs.out
      to: notify.in
    - from: notify.out
      to: end.in
