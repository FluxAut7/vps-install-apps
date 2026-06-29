# VPS Installer

Instalador CLI interativo para VPS Debian 12 e Ubuntu 22.04/24.04, com Docker Swarm, Traefik, Portainer e receitas iniciais para ferramentas de automação.

## Comando alvo

```bash
bash <(curl -sSL https://vps-setup.fluxaut.com.br)
```

## Como publicar

1. Crie um repositorio no GitHub com todo este diretorio.
2. Edite `bootstrap.sh` e troque `FluxAut7/vps-install-apps` pelo caminho real do repositorio.
3. Importe o repositorio no Vercel.
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
- Portainer
- PostgreSQL
- Redis
- n8n
- Uptime Kuma v1/v2
- Evolution API

## Mapa de dependencias

Antes de instalar uma ferramenta, o instalador mostra as dependências necessárias. Na v1, a base obrigatória e Docker Swarm + rede interna + Traefik + Portainer API. Apps como n8n e Evolution API também declaram PostgreSQL padrão, instalado automaticamente se ainda não existir.

## Estado local

O instalador salva configurações e credenciais em:

```text
/opt/vps-installer
```

Arquivos sensíveis ficam com permissao restrita. O backup criptografado exporta configurações e credenciais, mas não exporta dados persistidos de volumes, bancos ou arquivos das aplicações.

## Backup e migracao

No menu `Backup / Migração`:

- exporte configurações e credenciais em um arquivo `.enc`;
- copie o arquivo para outra VPS;
- instale a base na nova VPS;
- importe o backup;
- escolha se deseja manter domínios, trocar domínio base ou revisar domínio por domínio.

## Observacoes de seguranca

- O Portainer e usado como motor de deploy das ferramentas via API.
- Traefik e Portainer são instalados primeiro com `docker stack deploy`, pois o Portainer ainda não existe nesse momento.
- A stack do Portainer publica a porta `9000` para permitir inicializacao da API local. Em ambientes mais restritos, ajuste `templates/portainer.yml` antes de publicar.
- Use um repositorio privado somente se o bootstrap tiver uma forma segura de autenticar o download. Para o comando publico simples, o repositorio precisa ser publico.