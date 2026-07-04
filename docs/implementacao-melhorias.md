# Documentação técnica de implementação — Melhorias do VPS Installer

Este documento especifica as melhorias identificadas na comparação com os scripts de
referência (`references/` — SetupOrion v2.5.9 e v2.7.1), em ordem de prioridade, com
detalhes suficientes para implementação direta.

## Status de implementação

| # | Item | Status | Onde |
|---|---|---|---|
| 1 | `system_wait_stack` robusto + diagnóstico | ✅ Implementado | `lib/system.sh`, `lib/portainer.sh` |
| 2 | Validação de DNS pré-deploy | ✅ Implementado | `lib/dns.sh` + receitas |
| 3 | Smoke test HTTPS pós-deploy | ✅ Implementado | `lib/system.sh` (`system_wait_https`) |
| 4 | Catálogo data-driven + receita genérica | ✅ Implementado | `lib/appdef.sh`, `recipes/generic.sh`, `apps/` |
| 4a | Apps piloto (MinIO, RabbitMQ) | ✅ Implementado | `apps/minio/`, `apps/rabbitmq/` |
| 4b | Demais apps do catálogo (Chatwoot, Typebot, ...) | ⬜ Pendente | incremental, só manifestos |
| 5 | Menu "Ver credenciais" | ✅ Implementado | `installer.sh` |
| 6 | Remoção de stack com opção de volumes | ✅ Implementado | `installer.sh` |
| 7 | CI (shellcheck) + higiene do repositório | ✅ Implementado | `.github/workflows/ci.yml`, `.gitignore` |
| 7a | Testes bats | ✅ Implementado | `test/` (27 casos) |

Validação executada: `bash -n` (20 arquivos), `shellcheck -S warning` (limpo),
`bats test/` (27/27), render dos manifestos e parsing de convergência testados em
isolamento. Falta apenas validação em runtime numa VPS descartável (Docker Swarm +
Portainer + Let's Encrypt), conforme previsto na seção final.

## Convenções do projeto (obrigatórias em todo código novo)

Antes de implementar qualquer item, respeite as convenções existentes:

| Convenção | Regra |
|---|---|
| Shell | Bash com `set -Eeuo pipefail` herdado do `installer.sh` |
| Erros fatais | `fail "mensagem"` (definida em `lib/ui.sh`) |
| Saída para o usuário | `ui_info`, `ui_success`, `ui_warn`, `ui_title`, `ui_section`, `ui_pause` |
| Entrada do usuário | `ui_input`, `ui_password`, `ui_confirm`, `ui_menu` (com fallback dialog/texto) |
| Estado persistente | `state_set KEY valor [arquivo]` / `state_get KEY [arquivo]`; padrão `$STATE_DIR/config.env`, por app `$APP_STATE_DIR/<app>.env` |
| Segredos | `state_random_hex N`; arquivos de estado com `chmod 600` |
| Templates | Placeholders `__CHAVE__` substituídos por `stack_render template saida CHAVE valor ...` |
| Deploy | Sempre via `portainer_deploy_stack nome arquivo` (API do Portainer), nunca `docker stack deploy` direto (exceto base) |
| Registro | `state_register_app nome stack tipo domínio imagem arquivo` após deploy bem-sucedido |
| Versões | Catálogo fixado em `lib/catalog.sh`, com override por variável `VPSI_TESTED_<APP>_VERSIONS` |
| Idioma | Mensagens ao usuário em português |

Arquivos temporários: sempre em `$RUN_DIR` via `mktemp "$RUN_DIR/nome.XXXXXX"`.

---

## 1. Robustecer `system_wait_stack` (prioridade máxima)

### Situação atual

`lib/system.sh:93-110`. Deficiências:

1. O teste `$2 !~ /^0\//` considera sucesso qualquer serviço com ao menos 1 réplica —
   `1/2` passa, e um serviço em crash-loop que sobe e cai também pode passar.
2. Basta **um** serviço da stack ter réplica; os demais podem estar em `0/1`.
3. Em `lib/portainer.sh:89` a chamada é `system_wait_stack "$stack_name" 180 || true` —
   o timeout é silenciosamente ignorado e a receita imprime "instalado" mesmo com falha.
4. Em caso de falha, não há diagnóstico (logs, `docker service ps`).

### Especificação

Reescrever `system_wait_stack` com o contrato:

```
system_wait_stack <stack_name> [timeout_s=300]
# retorno 0: TODOS os serviços da stack convergiram (replicas atual == desejado)
# retorno 1: timeout ou stack sem serviços após período de graça
```

Algoritmo:

1. Período de graça inicial de até 30 s aguardando ao menos 1 serviço com o prefixo
   `<stack_name>_` aparecer em `docker service ls` (o Portainer cria a stack de forma
   assíncrona).
2. Loop de polling a cada 5 s até `timeout_s`:
   - Listar `docker service ls --filter label=com.docker.stack.namespace=<stack_name>
     --format '{{.Name}} {{.Replicas}}'` (usar o label, não regex de prefixo — evita
     colisão entre `n8n` e `n8n_cliente2`).
   - Convergiu ⇔ toda linha tem `X/X` com `X > 0` (comparar os dois lados da barra;
     ignorar sufixos como `1/1 (max 1)` do modo global).
3. Feedback de progresso: a cada iteração, `ui_info` com contagem "N de M serviços
   prontos" apenas quando o número mudar (não poluir a tela).
4. Em timeout, imprimir diagnóstico antes de retornar 1:
   ```bash
   docker service ls --filter "label=com.docker.stack.namespace=$stack" 
   docker service ps --no-trunc --format '{{.Name}} {{.CurrentState}} {{.Error}}' <serviço-não-convergido>
   ```
   Mostrar apenas as últimas linhas relevantes (`head -5` por serviço) e a dica:
   `ui_warn "Logs: docker service logs <serviço>"`.

### Mudança em `portainer_deploy_stack`

Remover o `|| true` de `lib/portainer.sh:89`. Novo comportamento:

```bash
if ! system_wait_stack "$stack_name" 300; then
  ui_warn "A stack '$stack_name' foi criada no Portainer, mas os serviços não convergiram."
  if ! ui_confirm "Deseja manter a stack para diagnóstico? (Não = remover a stack)"; then
    portainer_remove_stack "$stack_name"
    fail "Instalação de '$stack_name' revertida."
  fi
  return 1
fi
```

As receitas devem checar o retorno: `portainer_deploy_stack ... || return 1` — assim
`state_register_app` e a mensagem de sucesso só executam após convergência (na reversão,
`fail` já aborta; no caso "manter para diagnóstico", a receita registra o app mesmo
assim para o inventário refletir a stack existente — registrar antes do `return 1`).

### Critérios de aceite

- Instalar n8n com imagem válida → converge e imprime sucesso.
- Instalar stack com imagem inexistente (forçar tag inválida) → timeout, diagnóstico com
  o erro `No such image`, oferta de reversão, inventário consistente com a escolha.
- Duas stacks `n8n` e `n8n_x` simultâneas → espera não confunde os serviços.

---

## 2. Validação de DNS pré-deploy

### Objetivo

Impedir o erro mais comum da categoria: pedir certificado Let's Encrypt para um domínio
que não aponta para a VPS (gera rate-limit de 5 falhas/hora por domínio).

### Novo módulo `lib/dns.sh`

Adicionar ao bloco de `source` do `installer.sh` (após `lib/system.sh`).

```
dns_public_ip            # ecoa o IP público da VPS (cache em variável global)
dns_resolve <dominio>    # ecoa os IPs A do domínio, um por linha
dns_check_domain <dominio>  # retorno 0 se algum A == IP público
dns_confirm_domain <dominio>  # fluxo interativo; retorno 0 = prosseguir
```

Detalhes:

- `dns_public_ip`: tentar em ordem `curl -fsS -4 --max-time 5` para
  `https://api.ipify.org`, `https://ifconfig.me/ip`, `https://icanhazip.com`; validar
  formato IPv4 com regex; cachear em `VPSI_PUBLIC_IP`. Fallback final:
  `hostname -I | awk '{print $1}'` com `ui_warn` de que o IP pode ser privado.
- `dns_resolve`: usar `getent ahostsv4 "$dominio" | awk '{print $1}' | sort -u`
  (não depender de `dig`/`nslookup`, que não estão na lista de pacotes base;
  alternativamente adicionar `dnsutils` a `system_install_base_packages` e usar
  `dig +short A` — **decisão: usar `getent`**, zero dependência nova).
- `dns_confirm_domain` (usada pelas receitas):
  1. Se `dns_check_domain` passar → `ui_success "DNS ok: <dominio> → <ip>"`, retorno 0.
  2. Se falhar → mostrar IPs resolvidos (ou "não resolve") vs. IP da VPS e perguntar
     `ui_confirm "O domínio não aponta para esta VPS. Instalar mesmo assim?"`.
     Prosseguir só com confirmação explícita. Isso cobre casos legítimos
     (DNS via proxy Cloudflare, propagação em andamento).
- Caso Cloudflare proxy: se o domínio resolve para IPs `104.16.0.0/13`, `172.64.0.0/13`
  ou `131.0.72.0/22`, exibir `ui_warn` específico: "Domínio atrás de proxy Cloudflare —
  o desafio HTTP do Let's Encrypt pode falhar; use modo DNS-only (nuvem cinza) durante
  a emissão." (detecção best-effort, não bloqueante).

### Pontos de integração

Chamar `dns_confirm_domain "$dominio" || return 0` imediatamente após cada `ui_input`
de domínio, antes de qualquer efeito colateral:

- `recipes/base.sh` — domínio do Portainer (e do Traefik, se houver dashboard).
- `recipes/n8n.sh:26-28` — `editor_domain` e `webhook_domain`.
- `recipes/uptime-kuma.sh`, `recipes/evolution-api.sh` — domínio do app.
- Receita genérica do item 4 — automático via manifesto.

### Critérios de aceite

- Domínio correto → mensagem verde, sem prompt extra.
- Domínio inexistente → aviso com IPs comparados e prompt; recusar aborta sem criar nada.
- VPS sem `curl` para fora (firewall) → fallback com aviso, nunca crash.

---

## 3. Smoke test HTTPS pós-deploy

### Objetivo

Confirmar ao usuário que o app respondeu com certificado válido, ou orientá-lo se o
Traefik ainda está emitindo.

### Função `system_wait_https` em `lib/system.sh`

```
system_wait_https <dominio> [timeout_s=120]
# retorno 0: HTTPS respondeu com certificado válido (qualquer status < 500)
# retorno 1: timeout
```

Algoritmo: loop de 10 s em 10 s com
`curl -fsS -o /dev/null --max-time 8 "https://$dominio"`; aceitar também códigos de
redirect/auth (usar `-w '%{http_code}'` sem `-f` e considerar sucesso `code >= 200 &&
code < 500`). Diferenciar as duas falhas:

- Erro TLS (`curl` exit 60) → "aguardando emissão do certificado" (esperado no início).
- Timeout/conexão recusada → "serviço ainda não respondeu".

No timeout final: `ui_warn` com as duas causas prováveis (DNS/proxy e emissão pendente)
e a dica `docker service logs traefik_traefik --tail 50 | grep -i acme`.

### Integração

Nas receitas, após `state_register_app`, antes do bloco final de mensagens:

```bash
system_wait_https "$dominio" 120 || true
```

Aqui o `|| true` é correto: o smoke test é informativo, não deve reverter a instalação
(a emissão do certificado pode legitimamente demorar mais que o timeout).

---

## 4. Catálogo data-driven de apps (expansão do catálogo)

### Problema

Cada app novo exige hoje: receita `.sh` completa, entrada em `dependencies_describe`,
entrada em `installer_tool_label`/`installer_tool_version`, item de menu em `tools_menu`.
Com esse custo, alcançar o catálogo da referência (~90 apps) é inviável.

### Arquitetura proposta

Novo diretório `apps/`, um manifesto por app + template YAML. Receita genérica única
que interpreta o manifesto. As 5 receitas atuais **não** são migradas na primeira fase
(continuam como estão); apps novos entram apenas via manifesto.

#### Formato do manifesto `apps/<slug>/app.env`

Arquivo `KEY=valor` shell-sourceável (mesma infraestrutura de `state_source`), sem
lógica. Exemplo `apps/minio/app.env`:

```bash
APP_SLUG="minio"
APP_LABEL="MinIO"
APP_DESCRIPTION="Object storage compatível com S3."
APP_CATEGORY="infra"            # infra | automacao | chat | dados | site | ia
APP_IMAGE_REPO="minio/minio"
APP_TESTED_TAGS="RELEASE.2025-04-22T22-12-26Z"   # CSV; primeira = default
APP_DOMAINS="APP_DOMAIN:Domínio do console, ex: minio.seudominio.com.br;S3_DOMAIN:Domínio da API S3, ex: s3.seudominio.com.br"
APP_SECRETS="MINIO_ROOT_PASSWORD:hex16"          # CSV nome:gerador (hex16|hex32|user)
APP_INPUTS="MINIO_ROOT_USER:Usuário admin:admin" # CSV nome:pergunta:default
APP_NEEDS_POSTGRES="false"                        # true → recipe_postgres_ensure_default + banco <stack>_db
APP_NEEDS_REDIS="false"                           # true → senha Redis gerada + serviço no template
APP_SUMMARY_LINES="Console: https://__APP_DOMAIN__;API S3: https://__S3_DOMAIN__;Usuário: __MINIO_ROOT_USER__;Senha: __MINIO_ROOT_PASSWORD__"
```

#### Template `apps/<slug>/stack.yml`

Mesmo formato dos templates atuais (`templates/*.yml`): placeholders `__STACK_NAME__`,
`__NETWORK_NAME__`, `__APP_IMAGE__`, mais os declarados no manifesto
(`__APP_DOMAIN__`, `__MINIO_ROOT_PASSWORD__`, ...). Os composes da referência
(`references/Orion-Setup-271.sh`, heredocs por função `ferramenta_<app>`) servem de
base para escrever cada template — **reescrever, não copiar**: nossos templates usam
rede overlay externa nomeada, labels Traefik v3 e segredos gerados (nunca fixos).

#### Receita genérica `recipes/generic.sh`

```
recipe_generic_install <slug>
```

Fluxo (espelha `recipes/n8n.sh` passo a passo):

1. Carregar manifesto com `state_source "apps/$slug/app.env"` em subshell de variáveis
   próprias (prefixar leitura, não poluir ambiente global — implementar
   `appdef_load <slug>` que faz o source e valida campos obrigatórios:
   `APP_SLUG`, `APP_LABEL`, `APP_IMAGE_REPO`, `APP_TESTED_TAGS`, template existente).
2. `dependencies_confirm` genérico: montar o texto a partir de
   `APP_NEEDS_POSTGRES`/`APP_NEEDS_REDIS` + base.
3. `dependencies_require_base`.
4. Sufixo de stack (`ui_input`), colisão via `portainer_stack_exists` — idêntico ao n8n.
5. Seleção de tag: `catalog_pick_one` sobre `APP_TESTED_TAGS` com override
   `VPSI_TESTED_<SLUG>_VERSIONS` (slug em maiúsculas, `-` → `_`).
6. Para cada item de `APP_DOMAINS` (separador `;`, campos por `:`): `ui_input` +
   `dns_confirm_domain` (item 2).
7. Para cada `APP_INPUTS`: `ui_input` com default.
8. Para cada `APP_SECRETS`: gerar (`hex16` → `state_random_hex 16`, etc.).
9. Se `APP_NEEDS_POSTGRES=true`: `recipe_postgres_ensure_default`, criar banco
   `<stack>_db`, expor `POSTGRES_HOST/POSTGRES_PASSWORD/POSTGRES_DATABASE` como
   placeholders.
10. `stack_render` com todos os pares; `portainer_deploy_stack || return 1`;
    `state_register_app` com `app_type=<slug>`; `state_set` de cada segredo/domínio no
    `$APP_STATE_DIR/<stack>.env`.
11. `system_wait_https` no primeiro domínio; imprimir `APP_SUMMARY_LINES` com os
    placeholders substituídos (mesma função de escape do `stack_render`).

#### Menu

Em `tools_menu`, substituir os itens fixos 2–6 por um submenu por categoria gerado da
varredura de `apps/*/app.env` (ordenado por `APP_LABEL`), mantendo as 5 receitas
existentes como entradas manuais na categoria correspondente. `installer_tool_label`
ganha fallback: se existir `apps/<tipo>/app.env`, usar `APP_LABEL`.

#### Ordem de entrada dos apps (validar um a um antes do próximo)

1. MinIO, RabbitMQ (infra; pré-requisitos do Chatwoot)
2. Chatwoot, Typebot, Flowise
3. Qdrant, pgvector (variação do postgres — avaliar flag no recipe existente)
4. MySQL + phpMyAdmin, Metabase
5. Ollama + Open WebUI, Langflow
6. WordPress

### Critérios de aceite

- `recipe_generic_install minio` instala MinIO fim a fim sem código específico.
- Manifesto com campo obrigatório ausente → `fail` com mensagem clara antes de
  qualquer efeito colateral.
- App genérico aparece no painel (`show_status`), no update e no backup como os demais.

---

## 5. Menu "Ver credenciais"

### Objetivo

Equivalente ao `dados_vps` da referência: consultar URLs e segredos de qualquer app
instalado sem grep manual em `/opt/vps-installer`.

### Implementação

Função `installer_show_credentials` em `installer.sh`:

1. Listar apps de `$STATE_DIR/apps.tsv` num `installer_menu_with_summary` (mesmo padrão
   de `installer_import_existing_stack_interactive`, `installer.sh:694`).
2. Ao escolher, exibir o conteúdo de `$APP_STATE_DIR/<app>.env` formatado:
   - Agrupar: primeiro APP_NAME/APP_TYPE/APP_DOMAIN/INSTALLED_AT, depois demais chaves.
   - Valores passam por `printf '%b'`? **Não** — os valores foram gravados com
     `printf '%q'` (`state_env_escape`); para exibir, fazer `state_source` do arquivo e
     imprimir as variáveis já des-escapadas, iterando sobre as chaves obtidas com
     `awk -F= '{print $1}' arquivo`.
   - Incluir o item especial "Portainer" que mostra `$STATE_DIR/portainer.env`.
3. Antes de exibir, `ui_confirm "As credenciais aparecerão em texto claro na tela. Continuar?"`.
4. Nunca gravar a saída em arquivo nem em log.

Menu: novo item em `tools_menu` ("Ver credenciais de uma ferramenta") e em
`portainer_menu` ("Ver credenciais do Portainer").

---

## 6. Remoção de stack com opção de volumes

### Situação atual

`remove_stack_menu` remove via `portainer_remove_stack` e preserva volumes sempre.

### Especificação

Após a remoção da stack bem-sucedida:

1. Listar volumes órfãos da stack:
   `docker volume ls --filter "label=com.docker.stack.namespace=<stack>" -q`.
   Fallback (volumes sem label, criados por nome): filtrar `docker volume ls -q` por
   prefixo `<stack>_`.
2. Se houver volumes, exibi-los e perguntar com **confirmação dupla**:
   - `ui_confirm "Apagar também os N volumes de dados listados? Esta ação é irreversível."`
   - Segunda etapa: `ui_input "Digite o nome da stack para confirmar a exclusão dos dados"`
     e comparar com o nome exato; qualquer divergência cancela.
3. Aguardar os contêineres da stack sumirem antes do `docker volume rm` (a remoção da
   stack é assíncrona — poll de até 60 s em `docker ps` filtrando pelo label da stack);
   volumes em uso falham individualmente com `ui_warn`, sem abortar os demais.
4. Registrar no estado: `state_remove_app` já é chamado hoje? Verificar — se a remoção
   atual não limpa o inventário, incluir `state_remove_app "$stack"` e remover o
   arquivo em `$STACKS_DIR`.

---

## 7. Qualidade contínua (CI)

### GitHub Actions `.github/workflows/ci.yml`

Dois jobs em `ubuntu-latest`, disparo em `push` e `pull_request`:

1. **shellcheck**: `shellcheck -x installer.sh bootstrap.sh lib/*.sh recipes/*.sh`
   (o `-x` segue os `source`; manter os `# shellcheck source=` já existentes).
   Severidade: falhar em `error` e `warning`.
2. **bats** (fase 2): testes unitários dos módulos puros, sem Docker:
   - `lib/stack.sh` — `stack_render` (escape de `/`, `&`, `|`), `stack_validate_file`.
   - `lib/state.sh` — `state_set`/`state_get` com valores contendo espaços, aspas,
     `$`; usar `VPS_INSTALLER_HOME` apontando para diretório temporário do teste.
   - `lib/dns.sh` (item 2) — `dns_check_domain` com resolvedor mockado (função
     `dns_resolve` sobrescrita no teste).

Adicionar badge no `README.md` após o primeiro workflow verde.

### Pré-requisito de higiene do repositório

Adicionar `references/` ao `.gitignore` antes de qualquer commit dessas melhorias —
são 60 mil linhas de código de terceiros que não devem ser versionadas no repositório
público.

---

## Ordem de implementação e dependências

| Fase | Itens | Dependências | Risco |
|---|---|---|---|
| 1 | `.gitignore` de `references/` + CI shellcheck (7) | — | nulo |
| 2 | `system_wait_stack` robusto (1) | — | baixo; testar com as 5 receitas atuais |
| 3 | `lib/dns.sh` + integração nas receitas (2) | — | baixo |
| 4 | `system_wait_https` (3) | fase 3 recomendada | nulo (informativo) |
| 5 | Ver credenciais (5) e remoção com volumes (6) | — | baixo |
| 6 | Receita genérica + manifestos (4), 2 apps piloto (MinIO, RabbitMQ) | fases 2–4 | médio; validar app a app |
| 7 | Demais apps do catálogo | fase 6 | incremental |
| 8 | bats (7, fase 2) | — | nulo |

Cada fase deve ser um commit (ou PR) independente, testado numa VPS descartável
(Debian 12 ou Ubuntu 24.04) com o fluxo completo: preparar base → instalar app →
painel → backup/export → remover.
