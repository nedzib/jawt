# Ejemplos

Nodos y workflows de ejemplo para JAWT.

## Estructura

```text
examples/
├── nodes/
│   ├── notify/          # notificación de macOS (osascript, item-aware)
│   ├── pr-assigned/     # PRs asignados a @me (array `items` con rama)
│   ├── pr-open/         # PRs abiertos de @me
│   ├── pr-review/       # PRs donde soy revisor directo (array `items` + autor)
│   ├── herdr-worktree/  # abre/crea el worktree de Herdr de una rama
│   └── herdr-agent/     # inicia un agente en un pane y le envía un prompt
└── workflows/
    ├── notify-pr-review.workflow
    ├── notify-prs-open.workflow
    └── review-assigned.workflow
```

## Requisitos

- `gh` (GitHub CLI) autenticado.
- `osascript` (incluido en macOS) para las notificaciones.
- El daemon corriendo si quieres las ejecuciones programadas.

`review-assigned.workflow` requiere además `herdr` (servidor corriendo) y
el agente de revisión (`claude` por defecto) en el `PATH`.

## Instalar los nodos

Copia los nodos a la carpeta global del usuario:

```text
cp -R examples/nodes/* ~/.config/jawt/nodes/
```

## Usar los workflows

Copia un workflow a la carpeta de tu repositorio:

```text
cp examples/workflows/notify-pr-review.workflow tu-repo/.jawt/workflows/
```

El nodo `pr-review` infiere el repositorio desde el remote `origin`
del repo git donde corre jawt. Si lo necesitas, puedes pasarlo
explícito con el input opcional `repo`:

```yaml
    prs:
      type: pr-review
      repo: "owner/repo"
```

Valida y ejecuta:

```text
jawt validate
jawt workflow run notify-pr-review
```

## Revisar PRs asignados con Herdr

`review-assigned` compone nodos granulares en una cadena de `multiplex`
(fan-out por item):

```text
queue → multiplex → worktree → multiplex → notify → multiplex → agent
```

`queue` (`pr-review`) busca los PR donde soy **revisor directo** (no por
equipo): filtra `review-requested:@me` verificando `requested_reviewers`.
Por cada PR:

1. `herdr-worktree` salta la rama si su worktree ya está abierto, lo abre
   si existe sin workspace, o trae la rama y lo crea si no existe. El
   worktree se crea con el nombre `<autor>_<número>` (vía `--path`).
2. `notify` muestra una notificación de macOS (solo si hubo acción).
3. `herdr-agent` inicia un agente en el pane del worktree y le envía el
   prompt de revisión.

Cada nodo de fan-out enriquece su `item` y lo re-emite, de modo que la
salida se encadena al siguiente `multiplex`. Configura `cwd` (raíz del
repo), `repo` (`owner/repo`) y `kind` (agente) en el workflow:

```yaml
    queue:
      type: pr-review
      label: "Buscar PRs de revisión"
      repo: "owner/repo"
    worktree:
      type: herdr-worktree
      label: "Abrir worktree"
      cwd: "/Users/tu/ruta/al/repo"
    agent:
      type: herdr-agent
      label: "Revisar con agente"
      kind: claude
      prompt: "Revisa el PR {number} ({branch})..."
```

El campo opcional `label` sustituye al `id` en el grafo, para dar un
nombre legible a cada nodo (ej. `Buscar PRs de revisión` en vez de
`queue`).

El `prompt` acepta los placeholders `{number}`, `{branch}`, `{url}` y
`{title}` (sustituidos desde el item).

Se ejecuta a demanda (sin `schedule`):

```text
jawt workflow run review-assigned
```
