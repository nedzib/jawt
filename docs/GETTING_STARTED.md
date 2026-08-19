# Guía de instalación y uso

Guía paso a paso para instalar JAWT y usarlo en un repositorio
existente.

## 1. Requisitos

- Ruby >= 3.1 (recomendado 3.3+).
- macOS o Linux con terminal (`zsh` o `bash`).
- Git.

## 2. Instalación

El gem aún no está publicado en rubygems.org, así que se instala desde
el código fuente:

```text
git clone <url-del-repo> jawt
cd jawt
gem build jawt.gemspec
gem install ./jawt-0.1.0.gem
```

Verifica la instalación:

```text
jawt --version
```

Debería imprimir `jawt 0.1.0`.

## 3. Inicializar en un repositorio existente

Entra al repositorio donde quieras usar JAWT y ejecuta:

```text
cd tu-repositorio
jawt init
```

Esto crea:

```text
tu-repositorio/
└── .jawt/
    └── workflows/          # aquí viven tus workflows

~/.config/jawt/
├── nodes/                  # nodos instalados por el usuario
└── config.toml             # configuración global
```

Los workflows pertenecen al repositorio (se versionan con Git); los
nodos son globales del usuario.

## 4. Ver los nodos disponibles

```text
jawt node list
```

JAWT incluye nodos base listos para usar:

```text
start       (base)
end         (base)
condition   (base)
multiplex   (base)
run         (base)
```

## 5. Crear un nodo propio (opcional)

Los nodos son componentes reutilizables que tú programas:

```text
jawt node create saluda
jawt node edit saluda
```

Esto crea `~/.config/jawt/nodes/saluda/` con dos archivos:

- `node.toml`: declara inputs, outputs, puertos y comportamiento.
- `main.sh`: implementa la lógica.

Ejemplo de `node.toml`:

```toml
name = "saluda"
description = "Saluda por nombre"
exec = "main.sh"

[inputs]
nombre = { type = "string", required = true }

[outputs]
mensaje = "string"

[ports]
out = ["mensaje"]

[behavior]
cardinality = "single"
on_failure = "stop"
```

Ejemplo de `main.sh`:

```sh
#!/bin/sh
# inputs: $JAWT_INPUT_NOMBRE y JSON en stdin
# outputs: objeto JSON en stdout
echo "{\"mensaje\":\"hola $JAWT_INPUT_NOMBRE\"}"
```

El contrato es simple: los inputs llegan como variables de entorno
(`JAWT_INPUT_<NOMBRE>`) y como JSON en stdin; los outputs se devuelven
como JSON en stdout.

## 6. Crear un workflow

```text
jawt workflow create deploy
jawt workflow edit deploy
```

Escribe (o pega) el workflow. Los archivos `.workflow` usan YAML:

```yaml
workflow:
  name: deploy
  description: "Valida, testea y despliega"

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
      command: "gh pr comment --body 'revisado'"
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

Nota: el nodo `run` ejecuta el comando con `$SHELL -lic` por defecto
(zsh con tu `.zshrc`, aliases y PATH). Para un shell limpio, agrega:

```yaml
shell: /bin/sh
interactive: false
login: false
```

## 7. Validar

```text
jawt validate
```

Si todo está bien imprime `OK`. Si no, lista los errores de coherencia
(inputs faltantes, tipos incompatibles, ciclos, etc.).

## 8. Ver el mapa de flujos

```text
jawt workflow graph deploy
```

Dibuja el grafo del workflow en ASCII en la terminal.

## 9. Ejecutar

```text
jawt workflow run deploy
```

Muestra el estado de cada nodo y el resultado final.

## 10. Correr como servicio y usar la consola

JAWT puede correr como daemon para orquestar las ejecuciones:

```text
jawt daemon start
jawt daemon run deploy
jawt console
```

La consola muestra los workflows, el historial de ejecuciones y los
logs en vivo:

- `[r]` ejecutar el workflow seleccionado.
- `[↑]/[↓]` moverse entre workflows.
- `[q]` salir.

Para detener el daemon:

```text
jawt daemon stop
```

## 11. Múltiples repositorios

Registra los repositorios que quieres vigilar:

```text
jawt repo add /ruta/a/otro-repositorio
jawt repo list
jawt status
```

El daemon y `jawt validate` operan sobre todos los repositorios
configurados.

## 12. Versionar el workflow con Git

Los workflows viven en el repositorio, así que se comparten con el
equipo:

```text
git add .jawt/workflows/deploy.workflow
git commit -m "Agregar workflow de deploy"
```

Un compañero solo necesita tener instalado JAWT y los nodos que el
workflow declare en `requires`; no necesita tu copia de las
implementaciones de los nodos.
