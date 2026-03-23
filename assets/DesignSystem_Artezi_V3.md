# Design System Artezi V3

## 1. Direcao do sistema

O Design System da Artezi deve preservar a base visual ja reconhecivel do produto, mas evoluir sua execucao para um padrao mais premium, consistente e escalavel.

Essa nova versao parte de tres premissas:

- manter o que ja funciona bem no app atual
- corrigir inconsistencias visuais e funcionais
- transformar repeticao em sistema

## 2. Posicionamento visual

Artezi deve transmitir:

- confianca operacional
- seriedade B2B
- clareza em contexto de auditoria
- elegancia discreta
- rapidez de uso em campo

O visual nao deve parecer generico, mas tambem nao deve competir com a tarefa. O sistema precisa passar sensacao de produto premium por acabamento, espacamento, hierarquia e consistencia, e nao por excesso de efeito.

## 3. Principios de Design

### 3.1 Clareza acima de decoracao

Toda decisao visual deve ajudar o usuario a entender rapidamente:

- onde ele esta
- o que precisa fazer
- o que ja foi feito
- qual o estado atual da auditoria

### 3.2 Mobile-first real

O sistema nasce para uso em smartphone, com:

- leitura vertical
- acao com uma mao
- botoes grandes
- boa distancia entre elementos tocaveis
- componentes confortaveis com teclado aberto

### 3.3 Premium funcional

O produto deve parecer bem acabado e confiavel, com:

- superfices limpas
- sombras suaves
- bordas discretas
- tipografia forte
- roxo como assinatura controlada

### 3.4 Dominio orienta o sistema

Checklist, evidencias, progresso, conformidade e aprovacao nao sao casos especiais. Eles sao o centro do produto e devem orientar o DS.

### 3.5 Consistencia progressiva

Nem tudo precisa nascer perfeito, mas tudo novo deve nascer com logica reutilizavel.

## 4. Direcao visual recomendada

### 4.1 O que manter da base atual

- roxo como cor principal de marca e acao
- uso de superficies claras
- grandes botoes de acao no rodape
- cards com cantos arredondados
- campos amplos e legiveis
- estrutura simples e objetiva
- status visuais por cor

### 4.2 O que evoluir

- hierarquia de topo entre telas
- padronizacao de inputs
- padronizacao de modais e dialogs
- definicao mais clara de estados
- melhor contraste de textos secundarios
- melhor separacao entre feedback de sistema e status de dominio
- maior consistencia de espacamento

## 5. Foundations

## 5.1 Logos

### Assinaturas oficiais

O sistema passa a considerar tres arquivos oficiais de marca. No HTML, as previews devem usar os assets reais, sem redesenho manual.

- Logo institucional completa: [logo-artezi.png](c:\Users\giufe\OneDrive\Área de Trabalho\Codex\logo-artezi.png)
- Logo horizontal: [logo-escura.png](c:\Users\giufe\OneDrive\Área de Trabalho\Codex\logo-escura.png)
- Logo simbolo: [logo-artezi-icon.png](c:\Users\giufe\OneDrive\Área de Trabalho\Codex\logo-artezi-icon.png)

### Regras de uso

- `Logo institucional completa`
- Proposito: assinatura principal da marca para momentos institucionais e telas de entrada
- Usar em: splash, login e materiais institucionais
- Evitar em: headers pequenos e espacos compactos

- `Logo horizontal`
- Proposito: melhor formato para cabecalhos com branding e contextos com pouca altura
- Usar em: top bars branded, documentacao e apresentacoes do sistema
- Evitar em: areas muito estreitas ou telas em que o titulo ja seja dominante
- Fundo recomendado: claro, neutro e com respiro generoso

- `Logo simbolo`
- Proposito: versao compacta da marca para contextos reduzidos
- Usar em: atalhos, app mark, areas compactas e elementos reduzidos
- Evitar em: telas em que a leitura completa da marca seja importante

### Aplicacao recomendada no produto

- Splash e login: usar a logo institucional completa sobre o gradiente oficial
- Top bar com branding: usar preferencialmente a logo horizontal
- Espacos compactos: usar a logo simbolo

### Regra de consistencia

Nao alternar livremente entre logo central, logo horizontal e titulo puro sem criterio. O uso da marca no topo deve seguir a logica de navegacao da tela.

## 5.2 Cores

### Papel da cor

A cor principal deve sustentar:

- acoes primarias
- marca
- estados ativos
- foco e selecao

As demais cores devem ser mais contidas, para que o produto continue funcional e profissional.

### Paleta principal proposta

- `brand.primary`: `#7357D8`
- `brand.soft`: `#EEE9FF`
- `page.background`: `#F6F6FA`
- `brand.dark`: `#1B1830`
- `brand.darkAlt`: `#171A24`
- `brand.glow`: `#4E38A8`

- `neutral.0`: `#FFFFFF`
- `neutral.25`: `#FCFCFE`
- `neutral.50`: `#F6F6FA`
- `neutral.100`: `#EEEEF5`
- `neutral.200`: `#DFE0EA`
- `neutral.300`: `#C7C9D6`
- `neutral.400`: `#9A9EAE`
- `neutral.500`: `#72778A`
- `neutral.700`: `#34384A`
- `neutral.900`: `#171A24`

- `success.main`: `#22A861`
- `success.soft`: `#E8F7EF`
- `warning.main`: `#D9921A`
- `warning.soft`: `#FFF3DF`
- `error.main`: `#D64545`
- `error.soft`: `#FDEBEC`
- `info.main`: `#2F6FDE`
- `info.soft`: `#EAF1FF`

### Status de dominio

- `audit.completed`: `#22A861`
- `audit.pending`: `#E5A93D`
- `audit.in_progress`: `#7357D8`
- `audit.review`: `#2F6FDE`
- `audit.adjustment`: `#C96A1B`
- `audit.rejected`: `#D64545`

### Gradiente institucional

Uso recomendado:

- splash screen
- tela de login
- momentos de marca

Composicao:

- base superior: `#1B1830`
- base inferior: `#171A24`
- glow central: `#4E38A8`

### Tokens semanticos oficiais

- `color.bg.page`
- `color.bg.surface`
- `color.bg.subtle`
- `color.bg.inverse`
- `color.text.primary`
- `color.text.secondary`
- `color.text.tertiary`
- `color.text.inverse`
- `color.border.default`
- `color.border.soft`
- `color.border.focus`
- `color.action.primary`
- `color.action.primaryHover`
- `color.action.primaryDisabled`
- `color.action.secondary`
- `color.feedback.success`
- `color.feedback.warning`
- `color.feedback.error`
- `color.feedback.info`

### Regras de uso

- O roxo deve ser dominante apenas em acoes, foco, destaque e marca.
- Fundos da tela devem permanecer claros e discretos.
- O gradiente institucional deve ficar restrito a superficies de marca, e nao a telas operacionais comuns.
- Cores de status devem ser sempre acompanhadas de texto ou icone.
- Verde e vermelho devem ser usados com alta disciplina, principalmente no checklist.

## 5.3 Tipografia

### Direcao

A base atual funciona bem com uma sans-serif limpa. Para manter consistencia e boa leitura, o sistema deve seguir com uma familia simples e robusta.

### Familia recomendada

- Primaria: `Inter`
- Fallback: `system-ui`, `sans-serif`

### Escala tipografica

- `display.lg`: 40 / 48 / 700
- `heading.xl`: 32 / 40 / 700
- `heading.lg`: 28 / 36 / 700
- `heading.md`: 24 / 32 / 700
- `title.lg`: 20 / 28 / 600
- `title.md`: 18 / 26 / 600
- `title.sm`: 16 / 24 / 600
- `body.lg`: 18 / 28 / 400
- `body.md`: 16 / 24 / 400
- `body.sm`: 14 / 22 / 400
- `label.lg`: 16 / 24 / 600
- `label.md`: 14 / 20 / 600
- `label.sm`: 12 / 16 / 600
- `caption`: 12 / 16 / 400

### Regras de uso

- Titulo de tela: `heading.lg`
- Titulo de secao: `title.lg`
- Titulo de card: `title.md`
- Corpo principal: `body.md`
- Metadado e ajuda: `body.sm` ou `caption`
- Labels de botao: `label.lg`

## 5.4 Espacamento

### Escala oficial

- `space.4`
- `space.8`
- `space.12`
- `space.16`
- `space.20`
- `space.24`
- `space.32`
- `space.40`
- `space.48`

### Regras base

- Padding lateral de tela: `24`
- Distancia entre blocos principais: `24`
- Distancia entre label e campo: `8`
- Distancia entre itens de lista: `16`
- Distancia entre secoes dentro de card: `20`

## 5.5 Radius

### Escala oficial

- `radius.sm`: 10
- `radius.md`: 14
- `radius.lg`: 20
- `radius.xl`: 28
- `radius.full`: circular

### Uso recomendado

- Inputs: `radius.md`
- Cards: `radius.lg`
- Modal/dialog: `radius.xl`
- Pills e chips: `radius.full`
- Botao primario principal: `radius.lg`

## 5.6 Bordas

### Tokens

- `border.default`: 1
- `border.strong`: 1.5
- `border.focus`: 2

### Direcao

As bordas devem ser suaves e claras. O sistema nao deve parecer “pesado” ou excessivamente marcado.

## 5.7 Sombras

### Tokens

- `shadow.xs`: sombra muito sutil para superficies elevadas
- `shadow.sm`: cards e sheets
- `shadow.md`: dialogos e modais prioritarios

### Direcao

Sombras devem ser leves. O premium aqui vem da sutileza, nao do exagero.

## 5.8 Iconografia

### Direcao

Icones devem ser simples, lineares e consistentes.

Biblioteca oficial:

- `Material Symbols Outlined`

### Tamanhos

- `icon.sm`: 16
- `icon.md`: 20
- `icon.lg`: 24
- `icon.xl`: 28

### Regras

- A icone principal de acao costuma usar `24`
- Icones auxiliares em listas e campos usam `20`
- Em checklist, manter tamanho uniforme entre respostas

### Biblioteca oficial de icones

Os icones oficiais identificados e consolidados no HTML atual sao:

- `visibility`
- `edit`
- `delete`
- `share`
- `save`
- `calendar_month`
- `person`
- `logout`
- `picture_as_pdf`
- `add_circle`
- `warning_amber`
- `camera_alt`
- `more_vert`
- `more_horiz`
- `chevron_left`
- `search`
- `expand_more`
- `check_circle`
- `cancel`
- `remove_circle`
- `visibility_off`
- `tune`
- `person_search`
- `near_me`
- `content_copy`
- `info`
- `block`
- `check_box`
- `check_box_outline_blank`
- `indeterminate_check_box`

### Variantes visuais

O sistema passa a considerar duas apresentacoes oficiais:

- `Default / neutra`: icones lineares em neutro para biblioteca, navegacao e acoes gerais
- `Tonal Artezi`: icones em cards com fundo tonal da marca para showcases, atalhos e variacoes ilustrativas do sistema

### Agrupamento oficial no DS

Na versao final do Design System, a iconografia deve ser organizada em:

- `Biblioteca principal`
- `Variante padronizada`

Regras:

- os icones operacionais mais recentes nao devem ficar em uma secao separada de evolucoes
- novos icones validados no produto devem ser incorporados diretamente nessas duas bibliotecas
- a `Biblioteca principal` e a fonte oficial para leitura da familia completa
- a `Variante padronizada` representa a versao com fundo tonal quadrado usada no app

### Biblioteca principal

Deve consolidar:

- navegacao
- acoes de CRUD
- exportacao e compartilhamento
- filtros
- selecao
- estados de avaliacao
- bloqueios e informacao

### Variante padronizada

Deve consolidar os mesmos icones principais da biblioteca oficial, priorizando:

- acoes recorrentes de header
- filtros
- selecao
- copia
- envio
- estados que aparecem em cards e listas

### Checkboxes oficiais

Os estados oficiais de checkbox no DS sao:

- `Checkbox On`
- `Checkbox Off`
- `Checkbox Disabled`

Regras:

- `Checkbox On` deve seguir o padrao ativo usado em `planejamento-mensal-mvp.html`
- o estado ativo usa fundo roxo preenchido com check branco
- o estado `Off` usa fundo branco com borda neutra
- o estado `Disabled` usa base cinza e leitura de indisponibilidade

### Cores por contexto

- neutro: uso geral
- roxo: acoes destacadas e variacoes tonais da marca
- verde: conforme / sucesso
- vermelho: nao conforme / erro
- amarelo: alerta
- azul suave: nao observado quando houver leitura semantica distinta
- cinza frio suave: nao aplicavel quando houver leitura semantica distinta

## 6. Estrutura de layout

## 6.1 Pagina mobile

### Estrutura recomendada

- Top bar
- Conteudo principal
- Sticky action area

### Regras

- O CTA principal deve ficar no rodape em fluxos de formulario e checklist.
- O topo deve ter comportamento consistente entre telas.
- O conteudo precisa continuar legivel com teclado aberto.

## 6.2 Top bar

Padronizar tres modelos:

- `Top Bar - Branded`: logo da Artezi + back
- `Top Bar - Titulo`: back + titulo da tela + acoes
- `Top Bar - Fluxo`: back + titulo + acao contextual

### Regra

Nao alternar livremente entre logo central e titulo sem criterio. O uso precisa seguir logica de navegação.

## 6.3 Sticky bottom actions

Esse e um padrao central do produto.

### Regras

- um botao primario principal
- botao full width
- margem segura inferior
- segunda acao apenas quando realmente necessaria
- estados disabled sempre explicitos

## 7. Componentes-base

## 7.1 Button

### Proposito

Executar a acao principal ou secundaria da tela.

### Variacoes

- Primary
- Secondary
- Ghost
- Destructive
- Tonal

### Estados

- default
- pressed
- focused
- disabled
- loading

### Diretrizes de uso

- Apenas um `Primary` por tela.
- Primary deve ser usado nas acoes principais de cadastro, progresso, envio e confirmacao.
- Secondary deve apoiar a navegacao ou acao complementar.
- Ghost deve ser usado em contexto leve, como cancelar.

## 7.2 Text Field

### Proposito

Capturar texto curto, nome, CNPJ, endereco e dados estruturados.

### Estados

- default
- focused
- filled
- error
- disabled
- readonly

### Diretrizes de uso

- Campo deve ter label clara.
- Placeholder nao substitui label quando o campo e importante.
- Borda de foco deve ser semantica e consistente.
- Inputs passivos e inputs editaveis precisam parecer diferentes.

## 7.3 Search Field

### Proposito

Buscar cliente, auditoria, item ou responsavel.

### Estados

- idle
- typing
- result
- empty result
- loading

### Diretrizes de uso

- Busca deve indicar claramente quando ha resultados abaixo.
- Em listas de cliente, busca deve permanecer acessivel no topo.

## 7.4 Card

### Proposito

Agrupar informacao relacionada de forma legivel e modular.

### Estados

- default
- interactive
- selected
- disabled

### Diretrizes de uso

- Cards sao a principal superficie secundaria do produto.
- Devem ter padding consistente, borda suave e hierarquia interna clara.

## 7.5 Status Pill

### Proposito

Comunicar estado de auditoria, secao ou item.

### Estados

- info
- success
- warning
- error
- domain state

### Diretrizes de uso

- Sempre usar com texto curto.
- Pode ter icone apenas quando ajudar leitura.
- Nao usar apenas cor para comunicar significado.

## 7.6 Modal / Dialog

### Proposito

Exibir confirmacoes, formularios curtos ou processamento importante.

### Estados

- default
- loading
- success
- destructive confirmation

### Diretrizes de uso

- Dialog para confirmacao e decisao.
- Modal para formulario curto.
- Bottom sheet para selecao ou apoio contextual.
- Todos devem seguir a mesma familia visual.

## 7.7 Segmented Control

### Proposito

Alternar entre opcoes mutuamente exclusivas, como `Sim / Nao`.

### Estados

- default
- selected
- disabled

### Diretrizes de uso

- Usar para poucas opcoes.
- Quando a acao impactar campos seguintes, a mudanca precisa ser visualmente clara.

## 8. Componentes do dominio

## 8.1 Checklist Answer Selector

### Proposito

Registrar resposta do item de auditoria.

### Estados

- conforme
- nao conforme
- nao se aplica
- nao avaliado
- disabled

### Diretrizes de uso

- Ordem dos botoes deve ser fixa no sistema.
- Cada resposta deve ter cor, icone e label semantica.
- Estado selecionado precisa ter destaque muito claro.
- O tamanho da area de toque deve ser confortavel.

## 8.2 Checklist Item

### Proposito

Representar uma pergunta completa da auditoria.

### Estrutura

- pergunta
- seletor de resposta
- comentario
- anexo ou foto
- preview de evidencia

### Estados

- vazio
- respondido
- com evidencia
- com erro
- bloqueado

### Diretrizes de uso

- Esse e o componente mais importante do produto.
- Pergunta deve ter boa legibilidade e nao competir com a barra de acao.
- Comentario e evidencia devem ser secundarios, mas acessiveis.

## 8.3 Section Progress

### Proposito

Mostrar andamento da secao e da auditoria.

### Estados

- nao iniciada
- em andamento
- concluida

### Diretrizes de uso

- Progresso deve aparecer em contexto macro e micro.
- Barra e percentual precisam usar a mesma logica em todas as telas.

## 8.4 Audit Summary Row

### Proposito

Resumir status de secao ou auditoria.

### Estados

- concluida
- pendente
- em andamento
- reprovada

### Diretrizes de uso

- Deve ser facilmente escaneavel.
- Status, percentual e quantidade preenchida devem ter hierarquia clara.

## 8.5 Evidence Uploader

### Proposito

Registrar foto e anexo como evidencia.

### Estados

- vazio
- upload em andamento
- enviado
- erro
- removido

### Diretrizes de uso

- Foto precisa parecer associada ao item correto.
- Upload falho deve ter feedback imediato e acao de retry.

## 8.6 Responsibility Assignment Item

### Proposito

Relacionar pergunta a cliente ou operadora.

### Estados

- selecionado para operadora
- selecionado para cliente
- expandido
- recolhido

### Diretrizes de uso

- O padrao precisa ser altamente legivel porque envolve decisao operacional.
- Categoria e checkbox nao devem competir visualmente.

## 9. Padroes de tela

## 9.1 Login

### Direcao

Manter a identidade mais imersiva e escura, como assinatura da marca.

### Melhorias

- aumentar contraste dos campos
- reforcar label ou placeholder
- usar o gradiente institucional oficial da marca
- garantir alinhamento consistente entre logo, campos e CTA

## 9.2 Lista de clientes

### Direcao

Usar busca fixa, lista em card agrupado e CTA flutuante ou top action.

### Melhorias

- melhorar contraste das informacoes secundarias
- padronizar item de lista
- melhorar estado de busca ativa

## 9.3 Cadastro de cliente

### Direcao

Fluxo em card modular com CTA fixo.

### Melhorias

- padronizar labels
- reforcar agrupamento de secoes
- dar mais clareza aos estados do `Sim / Nao`
- alinhar melhor o bloco de responsaveis

## 9.4 Nova auditoria

### Direcao

Fluxo curto, decisao rapida, pouco atrito.

### Melhorias

- diferenciar melhor campo informativo de campo editavel
- padronizar seletor de cliente
- harmonizar calendario com o DS

## 9.5 Execucao de checklist

### Direcao

Prioridade total para leitura da pergunta, resposta rapida e registro de evidencia.

### Melhorias

- tornar o item de checklist mais modular
- melhorar ritmo vertical entre perguntas
- padronizar os icones de resposta
- reforcar o comportamento do CTA quando bloqueado

## 9.6 Resumo da auditoria

### Direcao

Tela de consolidacao, confianca e leitura rapida antes da visualizacao do relatorio.

Ela nao deve parecer tela de execucao. Deve parecer tela de revisao estrategica.

### Estrutura recomendada

- `Review Header Actions`
- `Strategic Summary Header`
- `Section Summary Card`
- `Question Summary Row`

### Padrões validados

#### Review Header Actions

Header enxuto para revisao, com:

- back
- logo centralizada em estado fechado
- gatilho `more_horiz`
- export / compartilhamento
- PDF
- editar

Regras:

- o topo nao deve competir com o resumo estrategico
- os icones devem seguir o conjunto oficial da iconografia
- em estado fechado, a logo permanece centralizada e o gatilho fica isolado na direita
- ao abrir o agrupamento, a logo some e as acoes aparecem em linha a esquerda do `close`
- as acoes abertas devem usar a variante tonal circular da marca
- evitar excesso de branding nessa tela
- evitar deixar as acoes sempre expostas quando nao forem a tarefa principal da tela

#### Strategic Summary Header

Bloco logo abaixo do header para resumir:

- cliente
- codigo e data da auditoria
- percentual concluido
- score final
- conformes e nao conformes

Regras:

- usar superficie clara e neutra
- evitar dark surface nesse contexto
- priorizar leitura horizontal rapida
- manter tipografia mais contida do que em telas institucionais
- evitar excesso de elementos decorativos
- o header e o resumo devem formar uma faixa continua, sem linha divisoria
- o fundo geral da tela pode voltar para o cinza claro do app abaixo desse bloco
- o score e o nome do cliente podem compartilhar a mesma cor de destaque
- status textual secundario pode ser removido se a conclusao e o score ja resolverem a leitura
- evitar cards auxiliares dentro do resumo quando nao agregarem valor

#### Section Summary Card

Card da categoria com:

- titulo da secao
- status pill
- percentual
- contador de itens preenchidos
- icone de expandir

Regras:

- pode existir sem borda, usando apenas sombra suave
- deve ter hierarquia clara entre titulo, status e percentual
- o percentual precisa ser visivel sem competir com o titulo
- em telas de resumo, priorizar sombra antes de borda para reduzir ruído visual
- usar cantos menos arredondados do que nos cards de formulários, quando a tela exigir leitura mais densa

#### Question Summary Row

Linha resumida da pergunta em modo revisao:

- numero da pergunta
- texto resumido
- icone de estado a direita

Estados oficiais:

- conforme
- nao conforme
- nao aplicavel
- nao observado
- nao respondido

Regras:

- o icone de estado deve aparecer sem container
- o texto da pergunta deve ser ligeiramente menor do que no checklist de execucao
- a numeração lateral ajuda orientacao e conferência
- nao mostrar metadados excessivos como peso e classificacao tecnica nessa vista
- os icones devem seguir os estados oficiais de avaliacao do DS
- o estado `nao respondido` pode usar icone de interrogacao
- o tamanho dos icones deve ser mais contido do que na tela de execucao

### Melhorias

- padronizar cards de secao
- ajustar peso de textos secundarios
- reforcar separacao entre status da secao e percentual
- consolidar o resumo estrategico como pattern oficial
- documentar os estados de pergunta em modo revisao

## 9.7 Operacao e agenda

### Direcao

Padrões operacionais precisam refletir exatamente as telas finais de planejamento, acompanhamento e agenda.

O objetivo dessa camada do DS e apoiar:

- filtros compactos
- leitura de status
- selecao multipla
- calendario de periodo
- agenda confirmada

### Estrutura recomendada

- `Compact Status Filters`
- `Operational Status Tags`
- `Auditor Multi-Select Filter`
- `Period Filter Calendar`
- `Confirmed Agenda List`

#### Compact Status Filters

Conjunto de filtros clicaveis com contagem resumida para telas de acompanhamento do mes.

Ordem oficial:

- `Total`
- `Confirmadas`
- `Recusadas`
- `Em andamento`
- `Nao agendadas`

Regras:

- usar formato compacto, sem cara de dashboard pesado
- o item ativo pode usar `brand soft`
- os demais itens devem ficar neutros
- a ordem deve refletir prioridade operacional e nao apenas ordem alfabetica

#### Operational Status Tags

Tags oficiais validadas nas telas finais:

- `Validar com cliente`
- `Pendente sugestao de data`
- `Pendente envio de nova proposta de data`
- `Recusada pelo auditor`
- `Confirmada`

Regras:

- `Validar com cliente` usa familia azul de informacao
- `Pendente sugestao de data` usa familia warning
- `Pendente envio de nova proposta de data` usa tom rose suave proprio
- `Recusada pelo auditor` usa familia de erro
- `Confirmada` usa familia de sucesso
- quando a tela ja estiver filtrada por status, evitar repetir a tag se ela ficar redundante

#### Auditor Multi-Select Filter

Filtro de auditor com selecao multipla e acao de selecionar todos.

Regras:

- usar o `Checkbox On` oficial do DS
- permitir selecao de 1 ou varios auditores
- o texto de cabecalho deve seguir a forma consolidada no produto: `Selecionar todos os auditores`
- os itens devem manter aparencia de lista simples e limpa

#### Period Filter Calendar

Calendario para filtro de periodo com:

- `Data inicial`
- `Data final`
- troca de mes
- troca de ano
- suporte a cruzar meses

Regras:

- a primeira e a ultima data usam o mesmo destaque roxo forte
- as datas entre elas usam roxo claro
- o calendario deve permitir selecao entre meses
- o limite de periodo e de `31 dias`
- quando o limite for ultrapassado, mostrar mensagem explicita em vermelho
- o bloqueio deve acontecer no aplicar, e nao por reajuste automatico silencioso

#### Confirmed Agenda List

Lista agrupada por dia para agenda de auditorias confirmadas.

Regras:

- agrupar por data no topo
- dentro do card mostrar apenas:
  - cliente
  - auditor
  - endereco
- nao repetir tag `Confirmada` quando o contexto da tela ja deixar isso implicito
- nao repetir a data dentro do card quando ela ja aparece no agrupamento superior

### Melhorias

- manter coesao entre filtros do header e filtros internos
- evitar modulos muito altos antes da lista principal
- privilegiar leitura rapida em mobile
- consolidar essa camada como referencia final para operacao do mes

## 9.8 Definir responsabilidades

### Direcao

Tela de configuracao com alta densidade, mas leitura simples.

### Melhorias

- padronizar accordion
- reforcar relacionamento entre categoria e itens internos
- melhorar o visual da confirmacao final

## 10. Estados do produto

## 10.1 Loading

Deve ter duas familias:

- inline loading
- blocking loading

## 10.2 Empty state

Precisa orientar o usuario sobre o proximo passo.

## 10.3 Error state

Precisa ser acionavel e objetivo.

## 10.4 Disabled state

Nao pode parecer apenas “apagado”. Deve comunicar claramente indisponibilidade.

## 10.5 Success feedback

Sempre que possivel, deve ser imediato e discreto.

## 11. Voz e conteudo

### Direcao

Tom claro, profissional e direto.

### Regras

- usar linguagem simples
- evitar termos vagos
- usar verbos claros em botoes
- manter status curtos e padronizados
- tratar mensagens de erro de forma objetiva

## 12. Melhorias prioritarias identificadas a partir dos prints

### 12.1 Alta prioridade

- padronizar top bars
- padronizar inputs
- padronizar checklist item
- padronizar status pills
- padronizar modais
- consolidar CTA fixo de rodape

### 12.2 Media prioridade

- harmonizar listas de cliente
- melhorar ritmo visual das telas de resumo
- formalizar estados de busca
- formalizar date picker dentro do sistema

### 12.3 Baixa prioridade

- refino do dark mode
- refinamento visual da splash e login
- polimento de microanimacoes

## 13. Ordem recomendada de construcao do DS

1. Cores e tokens
2. Tipografia
3. Espacamento, radius, borda e sombra
4. Top bar
5. Button
6. Text Field
7. Search Field
8. Card
9. Status Pill
10. Modal / Dialog
11. Sticky bottom action
12. Checklist Answer Selector
13. Checklist Item
14. Audit Summary Row
15. Responsibility Assignment patterns

## 14. Diretriz final

O DS da Artezi nao deve ser uma ruptura com o produto atual. Ele deve ser a versao organizada, refinada e premium do que o produto ja comecou a construir.

O objetivo nao e redesenhar por vaidade. O objetivo e criar um sistema que:

- aumente consistencia
- reduza retrabalho
- deixe o app mais confiavel
- facilite novas telas
- melhore o uso em campo
