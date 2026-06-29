# Publicar `vps-setup.fluxaut.com.br`

O dominio deve responder com o conteudo de `bootstrap.sh` via HTTPS. A forma mais simples e usar GitHub + Vercel.

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
5. Mantenha as configuracoes padrao de build. O arquivo `vercel.json` ja redireciona `/` e `/bootstrap.sh` para a funcao `api/bootstrap.js`.
6. Em `Settings > Domains`, adicione `vps-setup.fluxaut.com.br`.
7. No DNS do dominio, crie o registro que o Vercel indicar para esse subdominio. Normalmente sera um CNAME para o host informado pelo proprio Vercel.

## Teste

```bash
curl -fsSL https://vps-setup.fluxaut.com.br | head
bash <(curl -sSL https://vps-setup.fluxaut.com.br)
```

## Como funciona

- O Vercel hospeda apenas a entrada curta do instalador.
- A rota `https://vps-setup.fluxaut.com.br` retorna o conteudo de `bootstrap.sh`.
- O `bootstrap.sh` baixa o `.tar.gz` do repositorio GitHub.
- O `installer.sh` e as pastas `lib/`, `recipes/` e `templates/` rodam dentro da VPS.

## Atualizacoes

Sempre que voce fizer push no GitHub, o Vercel publica a nova versao do bootstrap. O instalador completo tambem sera baixado da branch configurada no `bootstrap.sh`.