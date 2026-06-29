# Publicar `vps-setup.fluxaut.com.br`

O domínio deve responder com o conteúdo de `bootstrap.sh` via HTTPS. A forma mais simples é usar GitHub + Vercel.

## Fluxo recomendado

1. Crie um repositorio no GitHub com todo este diretorio.
2. Edite `bootstrap.sh` e troque:

```bash
https://github.com/FluxAut7/vps-install-apps/archive/refs/heads/main.tar.gz
```

por:

```bash
https://github.com/FluxAut7/vps-install-apps/archive/refs/heads/main.tar.gz
```

3. Faca push para o GitHub.
4. No Vercel, clique em `Add New Project` e importe esse repositorio.
5. Mantenha as configurações padrão de build. O arquivo `vercel.json` já redireciona `/` e `/bootstrap.sh` para a função `api/bootstrap.js`.
6. Em `Settings > Domains`, adicione `vps-setup.fluxaut.com.br`.
7. No DNS do domínio, crie o registro que o Vercel indicar para esse subdomínio. Normalmente será um CNAME para o host informado pelo próprio Vercel.

## Teste

```bash
curl -fsSL https://vps-setup.fluxaut.com.br | head
bash <(curl -sSL https://vps-setup.fluxaut.com.br)
```

## Como funciona

- O Vercel hospeda apenas a entrada curta do instalador.
- A rota `https://vps-setup.fluxaut.com.br` retorna o conteúdo de `bootstrap.sh`.
- O `bootstrap.sh` baixa o `.tar.gz` do repositorio GitHub.
- O `installer.sh` e as pastas `lib/`, `recipes/` e `templates/` rodam dentro da VPS.

## Atualizacoes

Sempre que você fizer push no GitHub, o Vercel publica a nova versão do bootstrap. O instalador completo também será baixado da branch configurada no `bootstrap.sh`.