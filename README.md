# JAWT — Just Another Workflow Thing

JAWT es un orquestador de workflows basado en terminal, pensado
principalmente para developers y proyectos de software.

La idea es tener un runtime capaz de ejecutar workflows definidos por
el usuario mediante una composición de nodos independientes, donde la
salida de un nodo puede convertirse en la entrada del siguiente.

## Concepto

Cada repositorio que use JAWT tiene una carpeta propia:

```text
repo/
└── .jawt/
    └── workflows/
        ├── deploy.workflow
        ├── review.workflow
        └── release.workflow
```

Los workflows pertenecen al repositorio, mientras que los nodos son
componentes reutilizables instalados por el usuario.

Los nodos viven globalmente:

```text
~/.config/jawt/
├── nodes/
│   ├── start/
│   ├── end/
│   ├── condition/
│   ├── multiplex/
│   ├── run/
│   ├── ruby/
│   ├── http/
│   └── ...
└── config.toml
```

## Workflows como grafos

Un workflow no es necesariamente una secuencia lineal. Está compuesto
por nodos conectados.

```text
           ┌──────────────┐
           │ start        │
           └──────┬───────┘
                  │
                  ▼
           ┌──────────────┐
           │ git diff     │
           └──────┬───────┘
                  │
                  ▼
           ┌──────────────┐
           │ analyze      │
           └──────┬───────┘
                  │
                  ▼
           ┌──────────────┐
           │ condition    │
           └──────┬───────┘
                  │
            ┌─────┴─────┐
            ▼           ▼
        ┌───────┐   ┌────────┐
        │ tests │   │ notify │
        └───┬───┘   └────────┘
            │
            ▼
        ┌────────┐
        │ deploy │
        └───┬────┘
            │
            ▼
        ┌────────┐
        │ end    │
        └────────┘
```

Cada nodo recibe un contexto de entrada y produce una salida.

Por ejemplo, un nodo `run` podría ejecutar:

```text
git diff --stat
```

y producir:

```text
stdout
stderr
exit_code
```

El siguiente nodo puede consumir esos valores y utilizarlos para
continuar el workflow.

## Modelo de nodos

Un nodo es la unidad mínima de ejecución. JAWT define un contrato común
para que cualquier nodo sea coherente con el resto.

### Contrato de un nodo

Cada nodo vive en `~/.config/jawt/nodes/<nombre>/` y se compone de:

- `node.toml`: manifiesto que declara el contrato (inputs, outputs,
  puertos y comportamiento).
- Un ejecutable (`main.sh`, `main.rb`, `main.py`, ...) que implementa
  la lógica. Se resuelve con `exec` (por defecto `main.sh`).

El ejecutable recibe los inputs como variables de entorno
(`JAWT_INPUT_<NOMBRE>`) y como JSON en stdin. Devuelve los outputs como
un objeto JSON en stdout; si el nodo declara un único output, puede
devolver el valor en texto plano. Un exit code distinto de cero marca
el nodo como fallido.

```sh
#!/bin/sh
# inputs: $JAWT_INPUT_NOMBRE, JSON en stdin
# outputs: objeto JSON en stdout
echo "{\"saludo\":\"hola $JAWT_INPUT_NOMBRE\"}"
```

Ejemplo de `node.toml`:

```toml
name = "run"
description = "Ejecuta un comando en el shell"
exec = "main.sh"

[inputs]
command = { type = "string", required = true }
args    = { type = "array<string>", required = false }

[outputs]
stdout    = "string"
stderr    = "string"
exit_code = "integer"

[ports]
out   = ["stdout", "stderr", "exit_code"]
error = ["stderr", "exit_code"]

[behavior]
cardinality = "single"  # single | array
on_failure  = "stop"    # stop | continue | retry
```

### Reglas de coherencia

Las reglas que el validador comprueba para que un grafo sea coherente:

1. Tipos conocidos: `string`, `integer`, `float`, `boolean`,
   `array<T>`, `object` y `any`.
2. Todo `input` requerido debe estar conectado o tener un valor por
   defecto.
3. Una conexión `A.out -> B.in` es válida si el tipo de `A.out` es
   asignable al tipo de `B.in`.
4. Un `output` de tipo `array<T>` solo puede alimentar un nodo con
   `cardinality = "array"` o un `multiplex`.
5. Todo puerto referenciado en una conexión debe existir en el
   manifiesto del nodo.
6. El grafo es acíclico (DAG), salvo que un nodo declare
   explícitamente que soporta ciclos.
7. Un workflow tiene exactamente un nodo `start` y al menos un `end`.

### Puertos y enrutamiento

Los puertos son las salidas nombradas de un nodo. Puertos estándar:

- `out`: salida por defecto.
- `true` / `false`: salidas de un nodo `condition`.
- `error`: salida usada cuando el nodo falla (si existe).

## Nodos base

JAWT incluye un conjunto mínimo de nodos base, siempre disponibles:

- `start`: entrada del workflow. No tiene inputs. Produce el contexto
  inicial (parámetros, entorno y configuración).
- `end`: terminal. No tiene outputs. Marca el fin exitoso del workflow.
- `condition`: evalúa una expresión y enruta hacia `true` o `false`.
- `multiplex`: distribuye un array hacia una rama, una ejecución por
  elemento.

## Manejo de fallos

Todo nodo declara su comportamiento ante errores:

- `stop` (por defecto): aborta la ejecución del workflow. El estado
  final es `failed` y el error se propaga al `end`.
- `continue`: el nodo se marca como `failed` y la ejecución continúa
  por el puerto `error` (si existe) o por el flujo normal.
- `retry`: reintenta hasta `retry.max` veces con backoff; si agota los
  intentos, aplica `stop` o `continue`.

Un nodo falla cuando:

- El proceso termina con un exit code distinto de cero.
- Emite un output que no cumple su esquema.
- Lanza una excepción no controlada.

## Multiplexor y fan-out

Un nodo con `cardinality = "array"` puede producir más de un resultado
(por ejemplo, una lista de archivos, PRs o URLs).

El `multiplex` toma ese array y ejecuta la rama conectada una vez por
elemento, en paralelo (por defecto) o en secuencia. Un `join` opcional
recoge los resultados y los devuelve como array.

```text
      ┌───────────┐
      │ list-prs  │   -> [pr-1, pr-2, pr-3]
      └─────┬─────┘
            │
            ▼
      ┌───────────┐
      │ multiplex │
      └─────┬─────┘
            │  (una rama por elemento)
            ▼
      ┌───────────┐
      │ review    │
      └───────────┘
```

## Formato declarativo de un workflow

Además de la edición interactiva, un workflow puede declararse y
versionarse con Git. Los archivos `.workflow` usan YAML:

```yaml
workflow:
  name: deploy
  description: "Valida, testea y despliega"

  requires: [run, condition, github]

  nodes:
    start: { type: start }
    git-diff:
      type: run
      command: "git diff --stat"
    check:
      type: condition
      when: "${git-diff.exit_code} == 0"
    tests:
      type: run
      command: "make test"
      on_failure: stop
    notify:
      type: run
      command: "gh pr comment"
    end: { type: end }

  edges:
    - from: start.out
      to: git-diff.in
    - from: git-diff.out
      to: check.in
    - from: check.true
      to: tests.in
    - from: check.false
      to: notify.in
    - from: tests.out
      to: end.in
```

## Separación entre workflows y nodos

La arquitectura tiene dos niveles.

Repositorio (`.jawt/workflows/`): define qué quiere hacer el proyecto.

Usuario (`~/.config/jawt/nodes/`): define las capacidades disponibles.

Un workflow puede declarar sus dependencias:

```yaml
requires:
  - run
  - github
  - docker
```

Y JAWT valida si esas capacidades existen antes de ejecutar.

### Múltiples repositorios

`~/.config/jawt/config.toml` declara los repositorios que JAWT vigila:

```toml
repos = [
  "/Users/tu/proyecto-a",
  "/Users/tu/proyecto-b",
]
```

Se gestionan con la CLI:

```text
jawt repo add /Users/tu/proyecto-a
jawt repo remove /Users/tu/proyecto-a
jawt repo list
```

`jawt validate`, `jawt status` y el daemon operan sobre todos los
repositorios configurados (además del directorio actual).

## CLI

Toda la interacción con JAWT ocurre desde la terminal:

```text
jawt init
jawt workflow create deploy
jawt workflow edit deploy
jawt workflow run deploy
jawt workflow show deploy
jawt workflow graph deploy
jawt workflow list
jawt node create run
jawt node edit run
jawt node list
jawt repo add /Users/tu/proyecto
jawt repo remove /Users/tu/proyecto
jawt repo list
jawt validate
jawt status
jawt daemon start
jawt daemon stop
jawt daemon status
jawt daemon run deploy
jawt console
```

La edición puede ser interactiva:

```text
$ jawt workflow edit deploy
> add run
> add condition
> add deploy
> connect run -> condition
> connect condition.true -> deploy
> save
```

## Consola y daemon

JAWT corre como servicio (`jawt daemon start`) para orquestar las
ejecuciones de los workflows configurados. El daemon:

- Detecta y valida los workflows de `.jawt/workflows/`.
- Ejecuta workflows y mantiene el historial de ejecuciones.
- Expone un socket Unix para los clientes (CLI y consola).
- Persiste logs por ejecución en `~/.config/jawt/logs/`.

La consola (`jawt console`) se conecta al daemon y muestra en vivo:

- El estado de validación de cada workflow.
- Las ejecuciones activas y finalizadas.
- Los logs de la última ejecución.
- Comandos: `[r]` ejecutar, `[↑/↓]` mover, `[q]` salir.

Sin TTY, `jawt console --once` imprime el estado y termina.

## Mapa de flujos en la terminal

`jawt workflow graph deploy` dibuja el grafo del workflow en ASCII,
igual que los diagramas de este documento.

Durante una ejecución, el mapa se colorea según el estado de cada nodo
y muestra los valores que fluyen entre ellos.

## Validación y daemon

`jawt validate` ejecuta la validación de forma manual.

El daemon (`jawt daemon start`) mantiene la validación y orquesta las
ejecuciones de forma continua. Detecta:

- Nuevos repositorios.
- Nuevos workflows.
- Cambios en workflows.
- Nodos faltantes.
- Dependencias inválidas.
- Errores en las conexiones.
- Outputs incompatibles con inputs.
- Workflows inválidos.

## Principio del proyecto

JAWT no intenta dictar cómo debe automatizarse algo.

La filosofía es:

JAWT provides the runtime. You build the automation.

El sistema proporciona:

- Runtime.
- Modelo de nodos.
- Comunicación entre nodos.
- Manejo de inputs/outputs.
- Ejecución.
- Validación.
- CLI.
- Persistencia de workflows.

El usuario proporciona:

- Los nodos.
- La lógica de cada nodo.
- La composición del workflow.
- Las reglas de ejecución.

El resultado es un kit de automatización programable para developers,
donde un workflow puede ser tan simple como ejecutar tres comandos
encadenados o tan complejo como un grafo que combine CLI, APIs,
scripts, condiciones, agentes de IA y herramientas del proyecto.

## Roadmap

Hecho:

- Runtime y CLI (`init`, `validate`, `workflow`, `node`).
- Modelo de nodos y nodos base (`start`, `end`, `condition`,
  `multiplex`, `run`).
- Validador con reglas de coherencia.
- Mapa de flujos ASCII (`workflow graph`).
- Manejo de fallos (`stop`, `continue`, `retry`).
- Multiplexor con fan-out.
- Daemon como servicio + consola (`daemon`, `console`).
- Nodos de usuario: ejecución del `main.sh` propio de cada nodo.
- Múltiples repositorios configurados en `config.toml`.

Pendiente:

- `retry` con backoff real.
- `join` para recoger los resultados del fan-out.
- LaunchAgent/PLIST en macOS para arrancar el daemon al iniciar
  sesión.
- Auto-run al detectar cambios en un workflow.
- Colorear el mapa de flujos según el estado durante la ejecución.
- Empaquetar e instalar `jawt` como gem global.
