workflow:
  name: notify-prs-open
  description: "Notifica cada 7 minutos mis PR abiertos"

  schedule:
    every: 7m

  nodes:
    start: { type: start }
    prs:
      type: pr-open
    notify:
      type: notify
      title: "jawt - notify-prs-open"
      message: "Tienes ${prs.count} PR(s) abiertos"
    end: { type: end }

  edges:
    - from: start.out
      to: prs.in
    - from: prs.out
      to: notify.in
    - from: notify.out
      to: end.in
