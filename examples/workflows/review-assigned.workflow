workflow:
  name: review-assigned
  description: "Revisa mis PR asignados: worktree, notificación y agente por PR"

  schedule:
    every: 10m

  requires: [pr-review, herdr-worktree, notify, herdr-agent]

  nodes:
    start: { type: start }
    queue:
      type: pr-review
      repo: "owner/repo"
    fan1:
      type: multiplex
    worktree:
      type: herdr-worktree
      cwd: "/Users/tu/ruta/al/repo"
    fan2:
      type: multiplex
    notify:
      type: notify
    fan3:
      type: multiplex
    agent:
      type: herdr-agent
      kind: claude
      prompt: "Revisa el PR {number} (`{branch}`, repo owner/repo). Compara esta rama contra master (`git diff master...HEAD`) y haz un code review siguiendo las buenas prácticas del proyecto. Reporta solo hallazgos accionables, en español, con ruta, principio violado, problema y fix sugerido."
    end: { type: end }

  edges:
    - from: start.out
      to: queue.in
    - from: queue.out
      to: fan1.in
    - from: fan1.out
      to: worktree.in
    - from: worktree.out
      to: fan2.in
    - from: fan2.out
      to: notify.in
    - from: notify.out
      to: fan3.in
    - from: fan3.out
      to: agent.in
    - from: agent.out
      to: end.in
