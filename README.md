# Streaming pessoal

Stack Docker para um i5-8250U com UHD Graphics 620, 16 GB de RAM, SSD de 500 GB e HD de 1 TB. O torrent entra pelo qBittorrent, Sonarr e Radarr organizam a biblioteca, o Jellyfin serve o player.

Use só conteúdo e indexadores que você tem direito de baixar.

## Este hardware

O servidor é o notebook com i5-8250U, UHD 620, GeForce 930MX, 16 GB, SSD de 500 GB, HD de 1 TB e Ubuntu 26.04 LTS. A máquina em que este repositório está aberto não é esse servidor. O script `scripts/install-host.sh` recusa rodar se a CPU não for o 8250U.

O processador é um quad-core de 15 W. A UHD 620 faz Quick Sync: decode e encode de H.264, decode de HEVC 8 e 10 bit, encode de HEVC só em 8 bit, decode de VP9. Não tem AV1. Na prática isso é um ou dois transcodes 1080p ao mesmo tempo. Vários clientes em direct play não usam a GPU: o Jellyfin só entrega o arquivo, e o limite passa a ser o HD e a rede.

A 930MX não entra nesse caminho. O chip dela é o GM108, sem NVENC e sem NVDEC, então o Jellyfin não ganha transcode por ela. O compose monta `/dev/dri`, que é a UHD 620.

Os 16 GB sobram para a stack. Ociosa ela fica na faixa de 3 a 5 GB. O teto de 1 GB no FlareSolverr evita um Chromium disputando RAM com um transcode.

O SSD guarda o sistema, as imagens Docker e os bancos. O HD de 1 TB guarda torrent e biblioteca no mesmo filesystem. Um filme 1080p de 4 a 8 GB cabe bem; um remux 4K de 50 GB cabe cerca de quinze vezes no disco inteiro. Perfil de qualidade: 1080p, sem 2160p e sem remux.

No servidor, dentro do clone do repositório:

```bash
./scripts/install-host.sh
```

O script instala o Docker Engine e o plugin Compose pelo repositório oficial, o driver de vídeo da UHD 620 (`intel-media-va-driver`), coloca o usuário nos grupos `docker`, `video` e `render`, grava os GIDs no `.env` e cria `/srv/streaming` no SSD. Não instala driver NVIDIA. Saia da sessão e entre de novo para o grupo `docker` valer.

Monte o HD de 1 TB em `/mnt/media` antes do `make up`. O script avisa se esse mount ainda não existe.

## O que sobe por padrão

| Serviço | Função | Porta |
| --- | --- | --- |
| qBittorrent | Cliente torrent. Categorias separam TV e filme. | 8080, 6881 |
| Prowlarr | Cadastro único de indexadores, sincronizado com Sonarr e Radarr. | 9696 |
| FlareSolverr | Resolve desafio de browser para o Prowlarr. Só na rede interna. | — |
| Sonarr | Séries. Pasta raiz `/data/media/tv`. | 8989 |
| Radarr | Filmes. Pasta raiz `/data/media/movies`. | 7878 |
| Bazarr | Legendas ao lado do arquivo de vídeo. | 6767 |
| Jellyfin | Player. Bibliotecas em `/data/media/tv` e `/data/media/movies`. | 8096 |
| Seerr | Pedidos (sucessor do Overseerr e do Jellyseerr). | 5055 |

Plex e VPN não sobem no comando padrão. São arquivos extras, descritos abaixo.

## O que cada serviço faz

**qBittorrent** baixa e semeia. Não sabe o que é série ou filme: só recebe um torrent, grava em `/data/torrents/<categoria>` e informa o progresso. Sonarr usa a categoria `tv`, Radarr usa `movies`. No 8250U, deixe 2 ou 3 downloads ativos; verificação de hash e muitos torrents ao mesmo tempo disputam o HD com quem está assistindo. A Web UI fica na 8080. A senha inicial sai uma vez no log do container.

**Prowlarr** é o cadastro de indexadores. Sonarr e Radarr não guardam essa lista: pedem busca ao Prowlarr e recebem os resultados. Cadastrar o indexador nos dois apps duplica trabalho e senha. O banco fica no SSD (`CONFIG_ROOT`), porque é SQLite com muita leitura pequena.

**FlareSolverr** é um Chromium sem janela. Alguns indexadores exigem um desafio de browser antes de responder; o Prowlarr manda a URL para `http://flaresolverr:8191` e usa o cookie de volta. Não fale com a internet sozinho e a porta não é publicada. É o processo que mais pesa nesta CPU quando acorda, por isso o compose limita a memória em 1 GB. Se nenhum indexador precisar dele, o container pode sair do compose.

**Sonarr** cuida de séries. Você adiciona a série e a pasta raiz `/data/media/tv`. Ele pergunta ao Prowlarr, manda o torrent ao qBittorrent com a categoria `tv`, espera terminar e cria um hardlink em `/data/media/tv`, já renomeado. Hardlink só funciona porque download e biblioteca estão no HD de 1 TB, os dois vistos pelo container como `/data`. Perfil recomendado neste disco: 1080p, com um teto de tamanho por episódio para uma temporada não comer dezenas de gigabytes. O banco fica no SSD.

**Radarr** é o mesmo fluxo para filmes, com pasta `/data/media/movies` e categoria `movies`. Um filme, um arquivo. No HD de 1 TB, 1080p na faixa de 4 a 8 GB é o tamanho que deixa a biblioteca crescer. 2160p e remux enchem o disco com poucas dezenas de títulos.

**Bazarr** pega legenda depois que o arquivo já está na biblioteca. Lê a fila pelo Sonarr e pelo Radarr e grava o `.srt` ao lado do vídeo, então precisa escrever em `/data/media`. Prefira SRT em UTF-8. Legenda PGS ou ASS queimada na imagem obriga o Jellyfin a transcodificar, e esse é o caminho caro na UHD 620. SRT o cliente desenha sozinho, em direct play.

**Jellyfin** é o player. Biblioteca de séries em `/data/media/tv` e de filmes em `/data/media/movies`. Direct play de H.264 ou HEVC 1080p custa quase nada neste processador. Transcode usa a UHD 620: em Dashboard → Playback, aceleração Intel QuickSync, com H.264, HEVC, MPEG2, VC1 e VP9. Deixe AV1 desligado. Tone mapping de HDR é fraco nesta GPU; fonte SDR evita esse passo. Caminho de transcode: `/cache` (tmpfs de 2 GB na RAM). Limite a dois transcodes simultâneos. Trickplay e detecção de abertura varrem a biblioteca com os quatro núcleos; ligue isso depois, fora do horário de uso. Metadados e o banco ficam no SSD. Cliente de browser quase sempre transcodifica; o app do Jellyfin na TV ou no celular costuma dar direct play.

**Seerr** é a tela de pedido. A pessoa entra com a conta do Jellyfin, pede um título, e o Seerr manda para o Sonarr ou o Radarr. Não baixa e não toca vídeo. Só integra um media server por vez.

**Gluetun** (opcional, `make vpn`) coloca só o qBittorrent dentro do túnel. WireGuard neste i5 fica bem abaixo de um núcleo a 100 Mbps. OpenVPN gasta mais CPU; use WireGuard. Jellyfin, Sonarr e o resto continuam saindo pelo IP da casa. Com a VPN ligada, o host do download client passa a ser `gluetun`.

**Plex** (opcional, `make plex`) lê a mesma pasta. Neste servidor eu deixaria só o Jellyfin: dois servidores varrendo o HD de 1 TB duplicam a varredura, e transcode por hardware no Plex pede Plex Pass. A UHD 620 também está montada no container do Plex, se ele for o player escolhido.

## Por que essa combinação

- **Jellyfin em vez de Plex como padrão.** Os dois tocam a mesma pasta. Jellyfin é livre, não exige conta nem assinatura para transcode por hardware, e cabe inteiro nesta stack. Plex tem apps oficiais mais maduros e descoberta fora de casa mais simples; o arquivo `docker-compose.plex.yml` sobe os dois juntos. O Seerr só fala com um player por vez.
- **qBittorrent em vez de Transmission.** A API e as categorias encaixam no Sonarr e no Radarr sem mapa de caminho remoto.
- **Prowlarr em vez de cadastrar indexador em cada app.** Um lugar só, e o FlareSolverr fica ao lado quando o site pede desafio de browser.
- **Bazarr e Seerr.** Legenda e pedido são o que falta depois que Sonarr e Radarr já existem. Os dois são pequenos.
- **Sem Usenet neste compose.** SABnzbd entra depois, na mesma árvore `/data/usenet`, se você for por esse caminho. Não muda o layout de torrent.
- **Sem proxy reverso.** Na LAN, porta direta é o bastante. Fora de casa, o caminho simples é Tailscale (ou outro mesh) até o host, em vez de abrir 8080/8989/7878 na internet.

## Layout em disco

O SSD de 500 GB fica com `/srv/streaming/config`: bancos do Sonarr, Radarr, Prowlarr, Bazarr, Jellyfin e Seerr. O HD de 1 TB, montado em `/mnt/media`, é o `DATA_ROOT` inteiro. Sonarr e Radarr montam esse HD em `/data`, então a importação é um hardlink: o arquivo semeando e o arquivo na biblioteca são o mesmo inode. Torrent no SSD e biblioteca no HD quebram isso e passam a ocupar espaço nos dois discos.

```text
${DATA_ROOT}
├── torrents
│   ├── incomplete
│   ├── tv
│   └── movies
└── media
    ├── tv
    └── movies
```

ext4, btrfs ou xfs. exFAT não faz hardlink. Duas partições diferentes também não: `DATA_ROOT` tem que ser um mount só.

Dentro dos containers os caminhos são os mesmos. qBittorrent grava em `/data/torrents/tv`. Sonarr importa para `/data/media/tv`. Não use `/downloads`, `/tv` e `/movies` como volumes separados — o Docker trata cada volume como outro filesystem e a importação vira cópia.

## Subir

Isto roda no notebook servidor, depois do `install-host.sh` e do mount de `/mnt/media`. O Compose precisa ser 2.24 ou mais recente por causa do `!reset` no arquivo de VPN.

```bash
make up
```

`make up` cria os diretórios e sobe a stack. Na primeira vez as imagens levam um tempo.

| Onde | URL |
| --- | --- |
| qBittorrent | http://SERVIDOR:8080 |
| Prowlarr | http://SERVIDOR:9696 |
| Sonarr | http://SERVIDOR:8989 |
| Radarr | http://SERVIDOR:7878 |
| Bazarr | http://SERVIDOR:6767 |
| Jellyfin | http://SERVIDOR:8096 |
| Seerr | http://SERVIDOR:5055 |

A senha inicial do qBittorrent aparece uma vez no log:

```bash
docker logs qbittorrent 2>&1 | tail -n 50
```

## Ordem da configuração

1. **qBittorrent.** Troque a senha. Em Opções → Downloads, pasta incompleta `/data/torrents/incomplete` e modo de gerenciamento **Automático**. Crie as categorias `tv` → `/data/torrents/tv` e `movies` → `/data/torrents/movies`.
2. **Sonarr.** Settings → Media Management → pasta raiz `/data/media/tv`. Hardlinks ligados (é o padrão). Download client: host `qbittorrent`, porta `8080`, categoria `tv`.
3. **Radarr.** Igual, com pasta `/data/media/movies` e categoria `movies`.
4. **Prowlarr.** Settings → Apps: adicione Sonarr (`http://sonarr:8989`) e Radarr (`http://radarr:7878`) com a API key de cada um (Settings → General). Indexadores cadastrados aqui são enviados aos dois. Se um indexador exigir desafio de browser, adicione o FlareSolverr em `http://flaresolverr:8191`, marque uma tag e aplique essa tag só nesse indexador.
5. **Bazarr.** Conecte Sonarr e Radarr pelos mesmos hosts. Os caminhos já coincidem (`/data/media/...`), sem mapa extra.
6. **Jellyfin.** Bibliotecas Shows em `/data/media/tv` e Movies em `/data/media/movies`. Em Playback: Intel QuickSync, sem AV1, pasta de transcode `/cache`, no máximo dois transcodes. Trickplay e detecção de introdução ficam desligados no começo.
7. **Seerr.** Conecte o Jellyfin (`http://jellyfin:8096`), o Sonarr e o Radarr. Pedido aprovado cai no Sonarr ou no Radarr.

Entre containers, use o nome do serviço (`sonarr`, `qbittorrent`), não `localhost` e não o IP da LAN.

## VPN só no torrent

O override `docker-compose.vpn.yml` sobe o [Gluetun](https://github.com/qdm12/gluetun) e faz o qBittorrent usar a rede dele. Sonarr, Jellyfin e o resto continuam saindo pelo IP da casa.

Preencha no `.env` o provedor e as chaves WireGuard (ou usuário OpenVPN). Cada provedor tem variáveis próprias: [wiki do Gluetun](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers).

```bash
make vpn
```

Ajuste o download client no Sonarr e no Radarr: host `gluetun`, porta `8080`. A Web UI do qBittorrent continua em `http://SERVIDOR:8080`, publicada pelo Gluetun.

Para voltar ao modo sem VPN, pare o projeto inteiro e suba de novo o compose base. `make down` também remove o Gluetun e o Plex, porque os dois pertencem ao mesmo projeto.

```bash
make down
make up
```

Se o provedor encaminhar uma porta, coloque o número em `VPN_FORWARDED_PORT` e use esse número como porta de escuta no qBittorrent. Sem porta encaminhada o download segue funcionando.

## Plex

A UHD 620 já entra no compose principal. `make gpu` só avisa isso.

```bash
make plex   # adiciona o Plex na porta 32400; Jellyfin continua no ar
```

VPN e Plex juntos:

```bash
docker compose -f docker-compose.yml -f docker-compose.vpn.yml -f docker-compose.plex.yml up -d
```

## Operação

```bash
make ps
make logs
make down
make config   # resolve o YAML sem subir nada
```

Atualizar imagens:

```bash
docker compose pull
docker compose up -d
```

Não exponha qBittorrent, Sonarr, Radarr, Prowlarr, Bazarr nem Seerr na internet. São painéis de administração. Para assistir fora de casa, alcance o Jellyfin pela VPN/mesh do host.

Memória ociosa nesta máquina: cerca de 3 a 5 GB dos 16 GB. O FlareSolverr pode chegar a 1 GB quando resolve um desafio. Um transcode 1080p pela UHD 620 quase não tira CPU; um transcode em software, ou um arquivo AV1, ocupa os quatro núcleos e engasga.
