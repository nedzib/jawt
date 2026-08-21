# Ejemplos

Nodos y workflows de ejemplo para JAWT.

## Estructura

```text
examples/
├── nodes/
│   ├── notify/         # notificación de macOS (osascript)
│   ├── pr-assigned/    # PRs asignados a @me
│   ├── pr-open/        # PRs abiertos de @me
│   └── pr-review/      # PRs donde soy revisor directo
└── workflows/
    ├── notify-pr-review.workflow
    └── notify-prs-open.workflow
```

## Requisitos

- `gh` (GitHub CLI) autenticado.
- `osascript` (incluido en macOS) para las notificaciones.
- El daemon corriendo si quieres las ejecuciones programadas.

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
