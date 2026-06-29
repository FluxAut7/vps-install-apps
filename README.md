# VPS Installer

Instalador CLI interativo para VPS Debian 12 e Ubuntu 22.04/24.04, com Docker Swarm, Traefik, Portainer e receitas iniciais para ferramentas de automacao.

## Comando alvo

```bash
bash <(curl -sSL https://vps-setup.fluxaut.com.br)
```

## Como publicar

1. Crie um repositorio no GitHub com todo este diretorio.
2. Edite `bootstrap.sh` e troque `FluxAut7/vps-install-apps` pelo caminho real do repositorio.
3. Importe o repositorio no Vercel.
4. Aponte o dominio `vps-setup.fluxaut.com.br` para o projeto no Vercel.
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
- Evolution API

## Estado local

O instalador salva configuracoes e credenciais em:

```text
/opt/vps-installer
```

Arquivos sensiveis ficam com permissao restrita. O backup criptografado exporta configuracoes e credenciais, mas nao exporta dados persistidos de volumes, bancos ou arquivos das aplicacoes.

## Backup e migracao

No menu `Backup / Migracao`:

- exporte configuracoes e credenciais em um arquivo `.enc`;
- copie o arquivo para outra VPS;
- instale a base na nova VPS;
- importe o backup;
- escolha se deseja manter dominios, trocar dominio base ou revisar dominio por dominio.

## Observacoes de seguranca

- O Portainer e usado como motor de deploy das ferramentas via API.
- Traefik e Portainer sao instalados primeiro com `docker stack deploy`, pois o Portainer ainda nao existe nesse momento.
- A stack do Portainer publica a porta `9000` para permitir inicializacao da API local. Em ambientes mais restritos, ajuste `templates/portainer.yml` antes de publicar.
- Use um repositorio privado somente se o bootstrap tiver uma forma segura de autenticar o download. Para o comando publico simples, o repositorio precisa ser publico.