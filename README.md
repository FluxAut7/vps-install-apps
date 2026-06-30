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

- Docker e Docker Swarm single-node
- Rede overlay interna
- Traefik com HTTPS via Let's Encrypt
- Portainer LTS/STS
- PostgreSQL
- Redis
- n8n com runners externos obrigatórios
- Uptime Kuma v1/v2
- Evolution API

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

## Observações de segurança

- O Portainer é usado como motor de deploy das ferramentas via API.
- Traefik e Portainer são instalados primeiro com `docker stack deploy`, pois o Portainer ainda não existe nesse momento.
- A stack do Portainer publica a porta `9000` para permitir inicialização da API local. Em ambientes mais restritos, ajuste `templates/portainer.yml` antes de publicar.
- Use um repositório privado somente se o bootstrap tiver uma forma segura de autenticar o download. Para o comando público simples, o repositório precisa ser público.