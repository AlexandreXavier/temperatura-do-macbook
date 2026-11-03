# Temperatura

Monitor de temperatura para a barra de menus de Macs com processador Intel. Mostra a temperatura do CPU, as ventoinhas, o consumo, os processos mais pesados e uma explicação em português das causas prováveis do calor.

A app só lê os sensores. Nunca escreve no SMC, por isso as ventoinhas e os limites térmicos continuam a cargo do macOS. Não precisa de `sudo`.

## Compilar e abrir

```bash
scripts/build-app.sh
```

```bash
open build/Temperatura.app
```

O termómetro aparece na barra de menus, junto ao relógio. Clica nele para abrir o painel.

## Abrir ao iniciar sessão

Instala a app em `~/Applications` e regista-a no `launchd`. Volta a correr depois de recompilar, para atualizar a cópia instalada:

```bash
scripts/install-login.sh
```

Para remover a app e o arranque automático (o histórico é mantido):

```bash
scripts/uninstall-login.sh
```

## Linha de comandos

Mostrar uma leitura no terminal:

```bash
build/Temperatura.app/Contents/MacOS/Temperatura --sample
```

Gerar uma imagem do painel com dados reais (`--light` para o tema claro):

```bash
build/Temperatura.app/Contents/MacOS/Temperatura --snapshot painel.png
```

## Testes

```bash
swift test
```

## Dados

Uma média por minuto fica em `~/Library/Application Support/Temperatura/historico.csv`, com as colunas `timestamp,cpu_c,fan_pct,package_w`. O painel usa os últimos 7 dias desse ficheiro, que não é apagado automaticamente.

Para reduzir o calor gerado pela própria app, os sensores são lidos de 5 em 5 segundos. A lista de processos usa o `top`, que é mais pesado, e é lida de 2 em 2 minutos, ou de 20 em 20 segundos com o painel aberto.

## Limitações

- Não funciona em Macs com Apple Silicon, que usam outros sensores.
- Os nomes dos sensores foram atribuídos às chaves SMC de um MacBookPro11,2. Noutros modelos, alguns podem estar errados ou faltar.
- Os diagnósticos são regras simples sobre as leituras. A indicação de pó ou pasta térmica gasta é uma suspeita, porque nenhum sensor a consegue confirmar.
