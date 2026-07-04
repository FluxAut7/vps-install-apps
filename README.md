# VPS Installer

Instalador CLI interativo para VPS Debian 12 e Ubuntu 22.04/24.04, com Docker Swarm, Traefik, Portainer e receitas iniciais para ferramentas de automação.

## Comando alvo

```bash
bash <(curl -sSL https://vps-setup.fluxaut.com.br)
```

## Como publicar

1. Crie um repositório no GitHub com todo este diretorio.
2. Edite `bootstrap.sh` e troque `FluxAut7/vps-install-apps` pelo caminho real do repositório.
3. Importe o repositório no Vercel.
4. Aponte o domínio `vps-setup.fluxaut.com.br` para o projeto no Vercel.
5. Teste:

```bash
curl -fsSL https://vps-setup.fluxaut.com.br | head
bash <(curl -sSL https://vps-setup.fluxaut.com.br)
```

Durante desenvolvimento, a URL do pacote pode ser sobrescrita:

```bash
VPS_INSTALLER_ARCHIVE_URL="https://github.com/FluxAut7/vps-install-apps/archive/refs/heads/main.tar.gz" \
  bash <(curl -sSL https://vps-setup.fluxaut.com.br)
```

## O que a v1 instala

Base da VPS:

- Docker e Docker Swarm single-node
- Rede overlay interna
- Traefik com HTTPS via Let's Encrypt
- Portainer LTS/STS

## Catálogo de ferramentas (data-driven)

Todas as ferramentas ficam numa única tabela: o menu `Ferramentas` lista cada app
diretamente na raiz. Não há mais receitas dedicadas por app — tudo é definido por
manifesto. Cada app vive em `apps/<slug>/` com dois arquivos:

- `app.env`: manifesto declarativo (label, imagem, tags testadas, domínios, entradas,
  segredos gerados, dependências de Postgres/Redis, linhas de resumo e, quando o app é
  uma dependência compartilhada, linhas de estado `APP_STATE_LINES`).
- `stack.yml`: template do compose com placeholders `__CHAVE__`.

A receita genérica (`recipes/generic.sh`) interpreta o manifesto, coleta domínios e
entradas, gera segredos, renderiza o template e publica via Portainer. Todo app
aparece no painel, no menu de atualização e no backup da mesma forma.

Apps incluídos no catálogo:

| App | Categoria | Dependências |
|---|---|---|
| PostgreSQL | Banco relacional padrão | — |
| Redis | Cache / fila | — |
| n8n | Automação (editor, webhook, worker, runners) | PostgreSQL padrão + Redis na stack |
| Uptime Kuma | Monitoramento v1/v2 | — |
| Evolution API | API de WhatsApp | PostgreSQL padrão + Redis na stack |
| MinIO | Object storage S3 | — |
| RabbitMQ | Broker de filas | — |
| Qdrant | Banco vetorial | — |
| PostgreSQL + pgvector | Banco vetorial | — (banco interno) |
| Metabase | BI / dashboards | PostgreSQL padrão |
| Baserow | Planilha-banco no-code | PostgreSQL padrão |
| Typebot | Chatbots (builder + viewer) | PostgreSQL padrão |
| Langfuse | Observabilidade de LLM (v2) | PostgreSQL padrão |
| Langflow | Fluxos/agentes com LLM | PostgreSQL padrão |
| Mautic | Automação de marketing | MySQL próprio (na stack) |

Para adicionar outro, basta criar `apps/<slug>/app.env` e `apps/<slug>/stack.yml` —
nenhuma alteração de código é necessária. Placeholders disponíveis no template:
`__STACK_NAME__`, `__NETWORK_NAME__`, `__APP_IMAGE__`, `__APP_IMAGE_TAG__`, os campos
declarados no manifesto (domínios, entradas, segredos) e, quando aplicável,
`__POSTGRES_HOST__`/`__POSTGRES_PASSWORD__`/`__POSTGRES_DATABASE__` e `__REDIS_PASSWORD__`.

## Verificações de segurança e confiabilidade

- **Convergência de stack**: após cada deploy, o instalador aguarda todos os serviços da
  stack convergirem (réplicas completas). Em caso de falha, mostra o diagnóstico
  (`docker service ps` + erros) e oferece manter a stack para análise ou revertê-la.
- **Validação de DNS**: antes de instalar um app com domínio, o instalador compara o IP
  do domínio com o IP público da VPS e avisa se não baterem (inclusive detecção de proxy
  Cloudflare), evitando falhas de emissão de certificado no Let's Encrypt.
- **Smoke test HTTPS**: após o deploy, o instalador confirma se o domínio responde por
  HTTPS ou orienta caso o certificado ainda esteja sendo emitido.
- **Ver credenciais**: `Ferramentas > Ver credenciais` exibe URLs, usuários e senhas de
  um app instalado a partir do estado local (com aviso de exibição em texto claro).
- **Remoção com volumes**: a remoção de stack oferece apagar os volumes de dados, com
  confirmação dupla (digitar o nome da stack) para evitar exclusão acidental.

## Canal do Portainer

Durante a preparação da VPS, o instalador permite escolher o canal do Portainer:

- `LTS`: recomendado para produção.
- `STS`: novidades mais recentes, com ciclo de suporte mais curto.

A escolha define as imagens `portainer/portainer-ce:<canal>` e `portainer/agent:<canal>`.

## Mapa de dependências

Antes de instalar uma ferramenta, o instalador mostra as dependências necessárias. Na v1, a base obrigatória e Docker Swarm + rede interna + Traefik + Portainer API. Apps como n8n e Evolution API também declaram PostgreSQL padrão, instalado automaticamente se ainda não existir.

## Estado local

O instalador salva configurações e credenciais em:

```text
/opt/vps-installer
```

Arquivos sensíveis ficam com permissão restrita. O backup criptografado exporta configurações e credenciais, mas não exporta dados persistidos de volumes, bancos ou arquivos das aplicações.

## Backup e migração

No menu `Backup / Migração`:

- exporte configurações e credenciais em um arquivo `.enc`;
- copie o arquivo para outra VPS;
- instale a base na nova VPS;
- importe o backup;
- escolha se deseja manter domínios, trocar domínio base ou revisar domínio por domínio.

## Desenvolvimento e testes

O repositório roda `shellcheck` e uma suíte de testes `bats` a cada push e pull request
via GitHub Actions (`.github/workflows/ci.yml`).

Para rodar localmente:

```bash
# análise estática
shellcheck -x -S warning installer.sh bootstrap.sh lib/*.sh recipes/*.sh

# testes unitários dos módulos puros (sem Docker)
bats test/
```

Os testes cobrem `lib/stack.sh`, `lib/state.sh`, `lib/dns.sh` e `lib/appdef.sh`.

A estrutura do projeto:

```text
installer.sh          # ponto de entrada e menus
lib/                  # módulos: ui, state, system, dns, stack, portainer, backup,
                      #          dependencies, catalog, appdef
recipes/              # receitas de instalação/atualização (incl. generic.sh)
templates/            # composes das ferramentas nativas
apps/                 # catálogo data-driven (app.env + stack.yml por app)
test/                 # suíte bats
docs/                 # documentação técnica
```

## Observações de segurança

- O Portainer é usado como motor de deploy das ferramentas via API.
- Traefik e Portainer são instalados primeiro com `docker stack deploy`, pois o Portainer ainda não existe nesse momento.
- A stack do Portainer publica a porta `9000` para permitir inicialização da API local. Em ambientes mais restritos, ajuste `templates/portainer.yml` antes de publicar.
- Use um repositório privado somente se o bootstrap tiver uma forma segura de autenticar o download. Para o comando público simples, o repositório precisa ser público.