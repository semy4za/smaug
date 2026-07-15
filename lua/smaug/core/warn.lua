-- lua/smaug/core/warn.lua
--
-- Canal ÚNICO de aviso não-fatal (stderr) do Smaug.
--
-- Serve a "falha visível > acerto adivinhado" quando o dado é aceito mas merece
-- atenção do usuário (ex.: precisão de int64 > 2^53; CSV lido como 1 coluna com
-- separador suspeito). Não interrompe o fluxo; quem quiser silenciar redireciona
-- stderr por fora.
--
-- Era `local` no `core/series/init.lua` e só alcançava os submódulos da Series
-- via a tabela `I`. Promovido a módulo no item 12.10, quando o Anel 3 (io/csv)
-- passou a precisar do mesmo canal: escrever um segundo `io.stderr:write` ali
-- criaria dois canais de aviso divergentes — o oposto do "canal único" que este
-- comentário declara. Mesmo padrão de `core/display.lua` (apresentação) e
-- `core/errors.lua` (descrição-em-erro): utilitário transversal, fonte única.

return function(msg)
    io.stderr:write("smaug: aviso — " .. msg .. "\n")
end
