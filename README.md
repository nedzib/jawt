JAWT — Just Another Workflow Thing

JAWT es un orquestador de workflows basado en terminal, pensado principalmente para developers y proyectos de software.

La idea es tener un runtime capaz de ejecutar workflows definidos por el usuario mediante una composición de nodos independientes, donde la salida de un nodo puede convertirse en la entrada del siguiente.

Concepto

Cada repositorio que use JAWT tendrá una carpeta propia:

repo/
└── .jawt/
    └── workflows/
        ├── deploy.workflow
        ├── review.workflow
        └── release.workflow

Los workflows pertenecen al repositorio, mientras que los nodos son componentes reutilizables instalados por el usuario.

Los nodos vivirían globalmente:

~/.config/jawt/
├── nodes/
│   ├── run/
│   ├── condition/
│   ├── ruby/
│   ├── http/
│   └── ...
└── config.toml

Workflows como grafos

Un workflow no necesariamente es una secuencia lineal. Está compuesto por nodos conectados.

Por ejemplo:

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
          └────────┘

Cada nodo recibe un contexto de entrada y produce una salida.

Por ejemplo, un nodo run podría ejecutar:

git diff --stat

y producir:

stdout
stderr
exit_code

El siguiente nodo puede consumir esos valores y utilizarlos para continuar el workflow.

El usuario construye los nodos

Una característica fundamental de JAWT es que el usuario es quien crea y programa los nodos.

JAWT proporciona el runtime y un contrato común, pero no intenta implementar todas las posibles integraciones.

Por ejemplo, un usuario podría crear:

run
http
ruby
docker
github
llm
condition
parallel
transform

Cada nodo define cómo recibe información, qué hace y qué devuelve.

Esto permite que los nodos sean generales y reutilizables, independientemente del workflow donde se utilicen.

CLI

Toda la interacción con JAWT ocurre desde la terminal:

jawt init
jawt workflow create deploy
jawt workflow edit deploy
jawt workflow run deploy
jawt node create run
jawt node edit run
jawt node list
jawt validate
jawt status

La edición podría incluso ser interactiva:

$ jawt workflow edit deploy
> add run
> add condition
> add deploy
> connect run -> condition
> connect condition.true -> deploy
> save

También podría existir un formato declarativo para que los workflows puedan versionarse fácilmente con Git.

Separación entre workflows y nodos

La arquitectura tendría dos niveles.

Repositorio:

.jawt/workflows/

Contiene qué quiere hacer el proyecto.

Usuario:

~/.config/jawt/nodes/

Contiene las capacidades disponibles para hacerlo.

Esto permite que un repositorio comparta un workflow sin tener que incluir todas las implementaciones de los nodos.

El workflow podría declarar:

requires:
  - run
  - github
  - docker

y JAWT podría validar si esas capacidades existen.

Validación y daemon

JAWT tendría un proceso encargado de detectar y validar los repositorios configurados.

La idea inicial es utilizar un LaunchAgent/PLIST en macOS para ejecutar periódicamente el proceso de validación.

El proceso podría detectar:

* Nuevos repositorios.
* Nuevos workflows.
* Cambios en workflows.
* Nodos faltantes.
* Dependencias inválidas.
* Errores en las conexiones.
* Outputs incompatibles con inputs.
* Workflows inválidos.

También debería ser posible ejecutar la validación manualmente:

jawt validate

Principio del proyecto

JAWT no intenta ser una herramienta que dicte cómo debe automatizarse algo.

La filosofía sería:

JAWT provides the runtime. You build the automation.

El sistema proporciona:

* Runtime.
* Modelo de nodos.
* Comunicación entre nodos.
* Manejo de inputs/outputs.
* Ejecución.
* Validación.
* CLI.
* Persistencia de workflows.

El usuario proporciona:

* Los nodos.
* La lógica de cada nodo.
* La composición del workflow.
* Las reglas de ejecución.

El resultado sería una especie de kit de automatización programable para developers, donde un workflow puede ser tan simple como ejecutar tres comandos encadenados o tan complejo como construir un grafo que combine CLI, APIs, scripts, condiciones, agentes de IA y herramientas del proyecto.

JAWT — Just Another Workflow Thing.