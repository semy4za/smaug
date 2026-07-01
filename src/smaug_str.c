/* src/smaug_str.c
 *
 * Lifecycle e acesso do tipo string (offset-based, estilo Arrow).
 * Espelha o papel do smaug_core.c para os numéricos, mas em arquivo próprio
 * porque o lifecycle da string é de natureza diferente: alocação de tamanho
 * variável (buffer de bytes + offsets), com duas dimensões independentes
 * (nº de strings e total de bytes). Ver smaug_string.h e smaug_types.h.
 *
 * As operações sobre string (comparações, sort, take/filter — fases futuras)
 * ficarão em src/smaug_ops_str.c, separando lifecycle de operações como nos
 * numéricos (core vs ops).
 */

#include "smaug_string.h"
#include <stdlib.h>
#include <string.h>

/* Capacidade inicial do buffer de bytes quando não informada. Pequena: cresce
   conforme as strings entram. */
#define SMAUG_STR_BUFFER_INIT 16

/* ===================================================================
   Lifecycle
   =================================================================== */

smaug_series_str_t *smaug_str_create_with_capacity(size_t size, size_t buffer_capacity) {
    smaug_series_str_t *s = malloc(sizeof(smaug_series_str_t));
    if (!s) return NULL;

    /* offsets tem (capacity + 1) marcadores. Usamos `size` como capacity de
       elementos (a série nasce com `size` strings, todas NULL). O +1 é o
       marcador final do buffer. */
    size_t off_count = size + 1;
    s->offsets = malloc(off_count * sizeof(size_t));
    if (!s->offsets) { free(s); return NULL; }

    if (size == 0) {
        s->null_mask = NULL;
    } else {
        s->null_mask = malloc(size * sizeof(smaug_mask_t));
        if (!s->null_mask) { free(s->offsets); free(s); return NULL; }
        memset(s->null_mask, SMAUG_MASK_NULL, size);   /* tudo NULL por padrão */
    }

    /* Buffer de bytes. Mesmo com size>0, as strings começam todas NULL (0 bytes
       usados), então o buffer pode iniciar pequeno; cresce no set/append. */
    size_t bufcap = buffer_capacity > 0 ? buffer_capacity : SMAUG_STR_BUFFER_INIT;
    s->buffer = malloc(bufcap);
    if (!s->buffer) { free(s->null_mask); free(s->offsets); free(s); return NULL; }

    /* Todos os offsets começam em 0: nenhuma string tem conteúdo ainda, logo
       cada elemento i ocupa [0,0) (comprimento zero). Como o null_mask diz que
       são NULL, o comprimento zero é coerente (NULL tem 0 bytes). */
    for (size_t i = 0; i < off_count; i++) s->offsets[i] = 0;

    s->size            = size;
    s->capacity        = size;
    s->buffer_len      = 0;
    s->buffer_capacity = bufcap;
    s->offsets_owned   = true;   /* série normal é dona do seu offsets */
    s->meta.name           = "unnamed";
    s->meta.dtype          = "string";
    s->meta.is_view        = false;
    s->meta.external_alloc = false;
    return s;
}

smaug_series_str_t *smaug_str_create(size_t size) {
    return smaug_str_create_with_capacity(size, 0);
}

/* Cópia profunda independente: novos buffers, mesmo conteúdo. O clone NUNCA é
   view (external_alloc=false) — possui sua própria memória. */
smaug_series_str_t *smaug_str_clone(const smaug_series_str_t *s) {
    if (!s) return NULL;

    /* reserva o mesmo espaço de bytes do original (buffer_len), e `size` slots */
    smaug_series_str_t *c = smaug_str_create_with_capacity(
        s->size, s->buffer_len > 0 ? s->buffer_len : SMAUG_STR_BUFFER_INIT);
    if (!c) return NULL;

    /* copia offsets (size+1), null_mask (size) e os bytes usados do buffer */
    memcpy(c->offsets, s->offsets, (s->size + 1) * sizeof(size_t));
    if (s->size > 0)
        memcpy(c->null_mask, s->null_mask, s->size * sizeof(smaug_mask_t));
    if (s->buffer_len > 0)
        memcpy(c->buffer, s->buffer, s->buffer_len);

    c->buffer_len = s->buffer_len;
    c->meta.name  = s->meta.name;   /* mesmo nome (string literal/compartilhada) */
    return c;
}

void smaug_str_free(smaug_series_str_t *s) {
    if (!s) return;
    /* Posse dividida (A1): buffer e null_mask seguem external_alloc; offsets
       segue offsets_owned. Numa série normal ambos batem (dona de tudo). Numa
       view, external_alloc=true (não toca buffer/null_mask do pai) mas
       offsets_owned=true (libera o offsets rebaseado próprio). */
    if (!s->meta.external_alloc) {
        free(s->buffer);
        free(s->null_mask);
    }
    if (s->offsets_owned) {
        free(s->offsets);
    }
    free(s);   /* o struct em si sempre é heap-allocated */
}

/* View: janela zero-copy sobre `s`. Ver contrato completo em smaug_string.h.
   Checagem de limites overflow-safe (mesma forma do f64: `len > size - start`).
   Aloca só o array `offsets` (len+1 marcadores absolutos); buffer e null_mask
   são compartilhados com o pai. */
smaug_series_str_t *smaug_str_view(smaug_series_str_t *s, size_t start, size_t len) {
    if (!s || start > s->size || len > s->size - start) return NULL;

    smaug_series_str_t *v = malloc(sizeof(smaug_series_str_t));
    if (!v) return NULL;

    /* offsets próprio: (len+1) marcadores absolutos, copiados da janela do pai.
       Não rebaseados — apontam para dentro do buffer compartilhado, que é o
       mesmo ponteiro-base de s->buffer. */
    v->offsets = malloc((len + 1) * sizeof(size_t));
    if (!v->offsets) { free(v); return NULL; }
    for (size_t i = 0; i <= len; i++) v->offsets[i] = s->offsets[start + i];

    v->buffer          = s->buffer;                 /* compartilhado (mesmo base) */
    v->null_mask       = s->null_mask + start;       /* compartilhado, deslocado  */
    v->size            = len;
    v->capacity        = len;
    /* buffer_len/capacity da view descrevem a EXTENSÃO válida no buffer do pai
       que a view enxerga: do primeiro ao último offset da janela. Usados só
       como limites; a view não faz append sem antes destacar (COW). */
    v->buffer_len      = s->offsets[start + len];
    v->buffer_capacity = s->buffer_capacity;
    v->offsets_owned   = true;                        /* dona do offsets próprio */
    v->meta                = s->meta;
    v->meta.is_view        = true;
    v->meta.external_alloc = true;                    /* não libera buffer/null_mask */
    return v;
}

/* ===================================================================
   Construção em lote e acesso
   =================================================================== */

/* Cria a partir de um array de C-strings. Cada array[i]:
     - ponteiro NULL  -> elemento NULL (null_mask = SMAUG_MASK_NULL)
     - ""             -> string vazia VÁLIDA (distinta de NULL)
     - "texto"        -> string válida (comprimento via strlen; o conteúdo é
                          tratado como bytes — um \0 interno encerraria a
                          C-string, por definição de C-string)
   O tipo string trata o conteúdo como bytes crus (sem validar UTF-8). */
smaug_series_str_t *smaug_str_create_from_array(const char *const *array, size_t len) {
    if (!array) return NULL;

    /* Primeiro passo: soma os comprimentos para dimensionar o buffer de uma vez
       (evita realocações durante a construção). */
    size_t total = 0;
    for (size_t i = 0; i < len; i++) {
        if (array[i]) {
            size_t l = strlen(array[i]);
            /* proteção de overflow: o total não pode estourar size_t */
            if (l > (size_t)-1 - total) return NULL;  /* COV-EXCL-BR: total ~ SIZE_MAX; inalcancavel */
            total += l;
        }
    }

    smaug_series_str_t *s = smaug_str_create_with_capacity(len, total > 0 ? total : SMAUG_STR_BUFFER_INIT);
    if (!s) return NULL;

    /* Segundo passo: copia cada string para o buffer e preenche offsets/mask.
       offsets[0] já é 0 (do create). Para cada i: copia os bytes, avança o
       buffer_len, e grava offsets[i+1] = novo fim. */
    size_t pos = 0;
    for (size_t i = 0; i < len; i++) {
        if (array[i]) {
            size_t l = strlen(array[i]);
            if (l > 0) memcpy(s->buffer + pos, array[i], l);
            pos += l;
            s->null_mask[i] = SMAUG_MASK_VALID;          /* válido (inclui "" de comprimento 0) */
        } else {
            s->null_mask[i] = SMAUG_MASK_NULL;          /* NULL */
        }
        s->offsets[i + 1] = pos;             /* fim da string i = início da i+1 */
    }
    s->buffer_len = pos;
    return s;
}

/* Lê a string no índice idx. NÃO copia: devolve ponteiro para dentro do buffer
   e escreve o comprimento em *out_len. Retorna NULL se idx inválido ou elemento
   NULL (com *out_len = 0). Distingue "" (retorna ponteiro válido, *out_len=0,
   is_null=false) de NULL (retorna NULL, *out_len=0, is_null=true). */
const char *smaug_str_get(const smaug_series_str_t *s, size_t idx, size_t *out_len) {
    if (out_len) *out_len = 0;
    if (!s || idx >= s->size) return NULL;
    if (SMAUG_NULL(s->null_mask, idx)) return NULL;   /* elemento NULL */

    size_t start = s->offsets[idx];
    size_t end   = s->offsets[idx + 1];
    if (out_len) *out_len = end - start;
    /* Para "" (start==end), devolve um ponteiro válido para dentro do buffer
       (não-NULL) com comprimento 0 — assim "" se distingue de NULL no retorno. */
    return s->buffer + start;
}

bool smaug_str_is_null(const smaug_series_str_t *s, size_t idx) {
    if (!s || idx >= s->size) return true;        /* fora dos limites = "nulo" */
    return SMAUG_NULL(s->null_mask, idx);
}

/* ===================================================================
   Mutação (set/append) — gerência do buffer de tamanho variável
   =================================================================== */

/* Garante que o buffer comporta `extra` bytes além do buffer_len atual.
   Cresce geometricamente (como o grow numérico). 0 = ok, -1 = OOM (buffer
   intacto). */
static int str_buffer_reserve(smaug_series_str_t *s, size_t extra) {
    if (extra <= s->buffer_capacity - s->buffer_len) return 0;   /* já cabe */

    size_t need = s->buffer_len + extra;
    /* overflow guard na soma acima */
    if (need < s->buffer_len) return -1;  /* COV-EXCL-BR: overflow na soma buffer_len+extra; so com buffer_len ~ SIZE_MAX */

    size_t new_cap = s->buffer_capacity ? s->buffer_capacity : SMAUG_STR_BUFFER_INIT;  /* COV-EXCL-BR: buffer_capacity==0 inalcancavel via API publica (create garante bufcap>=INIT) */
    while (new_cap < need) {
        size_t grown = new_cap + (new_cap >> 1);      /* *1.5 */
        if (grown <= new_cap) { new_cap = need; break; }  /* overflow → usa need; COV-EXCL-BR: overflow no crescimento *1.5; so com new_cap ~ SIZE_MAX */
        new_cap = grown;
    }
    char *nb = realloc(s->buffer, new_cap);
    if (!nb) return -1;                                /* buffer intacto */
    s->buffer          = nb;
    s->buffer_capacity = new_cap;
    return 0;
}

/* Garante capacidade para 1 elemento a mais em offsets/null_mask (append). */
static int str_slots_reserve_one(smaug_series_str_t *s) {
    if (s->size < s->capacity) return 0;               /* já cabe */

    size_t new_cap = s->capacity ? (s->capacity + (s->capacity >> 1)) : 4;
    if (new_cap <= s->capacity) new_cap = s->capacity + 1;  /* COV-EXCL-BR: overflow ao dobrar capacity; so com capacity ~ SIZE_MAX */

    /* offsets tem (capacity + 1) elementos */
    size_t *no = realloc(s->offsets, (new_cap + 1) * sizeof(size_t));
    if (!no) return -1;
    s->offsets = no;

    smaug_mask_t *nm = realloc(s->null_mask, new_cap * sizeof(smaug_mask_t));
    if (!nm) {
        /* offsets já cresceu; encolhe de volta se possível (lição do grow
           numérico: realloc(p,0) liberaria p e deixaria dangling). */
        if (s->capacity > 0) {  /* COV-EXCL-BR: bloco de recuperacao de OOM de null_mask; inalcancavel na pratica (slots crescem atomicamente) */
            size_t *back = realloc(s->offsets, (s->capacity + 1) * sizeof(size_t));
            if (back) s->offsets = back;  /* COV-EXCL-BR: realloc de shrink falhando; defensivo */
        }
        return -1;
    }
    s->null_mask = nm;
    s->capacity  = new_cap;
    return 0;
}

/* --- Copy-on-Write detach (string) ---
   Chamado antes de qualquer mutação numa view (set, set_null, append,
   append_null). Diferente do detach numérico (dois buffers de tamanho fixo),
   a string tem três estruturas e os offsets são ABSOLUTOS na view (apontam pro
   buffer do pai). O detach:
     1. calcula a extensão de bytes da janela: [offsets[0], offsets[size]);
     2. aloca buffer privado com esses bytes (copiando a fatia do pai);
     3. aloca offsets privado REBASEADO (subtrai offsets[0] → começa em 0);
     4. aloca null_mask privado (cópia da janela).
   Após o detach a série é normal (offsets começam em 0, buffer só da janela),
   e os setters seguem sua lógica usual. O pai fica intacto.
   Guarda size==0: view vazia não copia bytes; desvincula as flags.
   Retorna 0 se ok, -1 se OOM (série intacta — falha segura: nada é substituído
   até que TODAS as alocações tenham sucesso). */
static int str_cow_detach(smaug_series_str_t *s) {
    if (!s->meta.is_view) return 0;            /* já é privada, nada a fazer */

    size_t base       = s->offsets[0];          /* offset absoluto do 1º elemento */
    size_t end        = s->offsets[s->size];    /* offset absoluto do fim da janela */
    size_t byte_count = end - base;             /* bytes da janela                 */

    if (s->size == 0) {                         /* view vazia: sem dados a copiar */
        /* offsets ainda tem 1 marcador (size+1=1). Rebaseia-o para 0 e privatiza
           buffer/null_mask como vazios, mantendo o struct coerente. */
        char *nb = malloc(SMAUG_STR_BUFFER_INIT);
        if (!nb) return -1;
        s->offsets[0]          = 0;
        s->buffer              = nb;
        s->null_mask           = NULL;
        s->size                = 0;
        s->capacity            = 0;
        s->buffer_len          = 0;
        s->buffer_capacity     = SMAUG_STR_BUFFER_INIT;
        s->meta.is_view        = false;
        s->meta.external_alloc = false;
        return 0;
    }

    /* aloca os três privados; só substitui após todos terem sucesso */
    size_t bufcap = byte_count > 0 ? byte_count : SMAUG_STR_BUFFER_INIT;
    char         *nb = malloc(bufcap);
    size_t       *no = malloc((s->size + 1) * sizeof(size_t));
    smaug_mask_t *nm = malloc(s->size * sizeof(smaug_mask_t));
    if (!nb || !no || !nm) { free(nb); free(no); free(nm); return -1; }

    if (byte_count > 0) memcpy(nb, s->buffer + base, byte_count);
    for (size_t i = 0; i <= s->size; i++) no[i] = s->offsets[i] - base;  /* rebaseia */
    memcpy(nm, s->null_mask, s->size * sizeof(smaug_mask_t));

    free(s->offsets);          /* offsets_owned=true: a view é dona; libera o antigo */
    s->buffer              = nb;
    s->offsets             = no;
    s->null_mask           = nm;
    s->capacity            = s->size;
    s->buffer_len          = byte_count;
    s->buffer_capacity     = bufcap;
    s->offsets_owned       = true;
    s->meta.is_view        = false;
    s->meta.external_alloc = false;
    return 0;
}

smaug_status_t smaug_str_set(smaug_series_str_t *s, size_t idx, const char *str, size_t len) {
    if (!s)             return SMG_ERR_ARGUMENT;
    if (idx >= s->size) return SMG_ERR_OOB;
    if (!str && len > 0) return SMG_ERR_ARGUMENT;   /* ponteiro nulo com len>0 */
    if (str_cow_detach(s) != 0) return SMG_ERR_NOMEM;

    size_t start   = s->offsets[idx];
    size_t old_len = s->offsets[idx + 1] - start;

    /* delta: quanto o buffer cresce (positivo) ou encolhe (negativo) */
    if (len > old_len) {
        /* MAIOR: precisa de (len - old_len) bytes extras. Reserva ANTES de mexer. */
        size_t extra = len - old_len;
        if (str_buffer_reserve(s, extra) != 0) return SMG_ERR_NOMEM;

        /* abre espaço: move o "rabo" (bytes após a string idx) para frente.
           memmove (regiões se sobrepõem). O rabo vai de [start+old_len, buffer_len)
           para [start+len, ...). */
        size_t tail_start = start + old_len;
        size_t tail_bytes = s->buffer_len - tail_start;
        if (tail_bytes > 0)
            memmove(s->buffer + start + len, s->buffer + tail_start, tail_bytes);

        /* grava a nova string no espaço aberto */
        if (len > 0) memcpy(s->buffer + start, str, len);  /* COV-EXCL-BR: len==0 inalcancavel aqui (bloco len>old_len implica len>0) */

        /* offsets seguintes sobem em `extra` */
        for (size_t i = idx + 1; i <= s->size; i++) s->offsets[i] += extra;
        s->buffer_len += extra;

    } else if (len < old_len) {
        /* MENOR: grava a nova string, depois fecha o buraco movendo o rabo para trás. */
        if (len > 0) memcpy(s->buffer + start, str, len);

        size_t shrink     = old_len - len;
        size_t tail_start = start + old_len;
        size_t tail_bytes = s->buffer_len - tail_start;
        if (tail_bytes > 0)
            memmove(s->buffer + start + len, s->buffer + tail_start, tail_bytes);

        for (size_t i = idx + 1; i <= s->size; i++) s->offsets[i] -= shrink;
        s->buffer_len -= shrink;

    } else {
        /* IGUAL: sobrescreve in-place. Nenhum offset muda, nada se desloca. */
        if (len > 0) memcpy(s->buffer + start, str, len);
    }

    s->null_mask[idx] = SMAUG_MASK_VALID;       /* set sempre torna válido */
    return SMG_OK;
}

smaug_status_t smaug_str_set_null(smaug_series_str_t *s, size_t idx) {
    if (!s)            return SMG_ERR_ARGUMENT;
    if (idx >= s->size) return SMG_ERR_OOB;
    /* Marca como NULL. Por convenção, um elemento NULL tem comprimento zero:
       removemos seus bytes do buffer (fecha o buraco) para manter o invariante
       de que o comprimento de i é offsets[i+1]-offsets[i]. Reusar a lógica do
       set com len 0 faz exatamente isso (grava "" e fecha o buraco), e depois
       marcamos o mask como NULL.
       set("",0) sobre idx já validado não cresce o buffer (encolhe ou no-op),
       logo não aloca; mas propagamos o status em vez de descartá-lo (o str_set
       legado devolve -1 só em !s/idx inválido/OOM, todos impossíveis aqui). */
    /* COW: o detach dispara dentro do smaug_str_set abaixo (primeira mutação
       numa view). A linha null_mask[idx] seguinte já opera no buffer privado. */
    smaug_status_t rc = smaug_str_set(s, idx, "", 0);
    if (rc != SMG_OK) return rc;   /* propaga (na prática impossível após validação acima); COV-EXCL-BR: rc sempre SMG_OK neste ponto (validacao acima ja garante) */
    s->null_mask[idx] = SMAUG_MASK_NULL;       /* e marca NULL (set deixou SMAUG_MASK_VALID) */
    return SMG_OK;
}

int smaug_str_append(smaug_series_str_t *s, const char *str, size_t len) {
    if (!s) return -1;
    if (!str && len > 0) return -1;
    if (str_cow_detach(s) != 0) return -1;   /* COW: destaca se for view; -1 se OOM */

    /* reserva 1 slot (offsets/mask) e os bytes da string */
    if (str_slots_reserve_one(s) != 0) return -1;
    if (str_buffer_reserve(s, len) != 0) return -1;

    /* a nova string começa no fim atual do buffer (offsets[size]) */
    size_t start = s->offsets[s->size];
    if (len > 0) memcpy(s->buffer + start, str, len);

    s->offsets[s->size + 1] = start + len;   /* novo marcador final */
    s->null_mask[s->size]   = SMAUG_MASK_VALID;          /* válido */
    s->size       += 1;
    s->buffer_len += len;
    return 0;
}

int smaug_str_append_null(smaug_series_str_t *s) {
    if (!s) return -1;
    if (str_cow_detach(s) != 0) return -1;   /* COW: destaca se for view; -1 se OOM */
    if (str_slots_reserve_one(s) != 0) return -1;

    /* NULL: comprimento zero — o offset final repete o anterior. */
    size_t start = s->offsets[s->size];
    s->offsets[s->size + 1] = start;         /* [start, start) = 0 bytes */
    s->null_mask[s->size]   = SMAUG_MASK_NULL;          /* NULL */
    s->size += 1;
    return 0;
}

/* ===================================================================
   Utilidades
   =================================================================== */

size_t smaug_str_count_nonnull(const smaug_series_str_t *s) {
    if (!s) return 0;
    size_t n = 0;
    for (size_t i = 0; i < s->size; i++)
        if (SMAUG_VALID(s->null_mask, i)) n++;
    return n;
}
