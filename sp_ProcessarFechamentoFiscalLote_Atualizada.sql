-- DROP PROCEDURE IF EXISTS dbo.sp_ProcessarFechamentoFiscalLote_Atualizada;

CREATE PROCEDURE dbo.sp_ProcessarFechamentoFiscalLote_Atualizada
(
    @StatusFiltro VARCHAR(20),
    @DataInicio DATETIME,
    @DataFim DATETIME,
    @SimularEstorno BIT
)
AS
BEGIN

	SET NOCOUNT ON;

    CREATE TABLE #FechamentoFiscal
    (
        VendaID INT,
        ClienteID INT,
        NomeCliente VARCHAR(200),
        StatusCliente VARCHAR(20),
        DataVenda DATETIME,
        StatusVenda VARCHAR(20),
        CanalID INT,
        NomeCanal VARCHAR(100),
        PercentualComissao DECIMAL(9,4),
        VendaItemID INT,
        ProdutoID INT,
        NomeProduto VARCHAR(200),
        CategoriaID INT,
        NomeCategoria VARCHAR(100),
        TaxaImpostoPadrao DECIMAL(9,4),
        Quantidade INT,
        ValorUnitario DECIMAL(18,2),
        ValorTotal DECIMAL(18,2),
        PercentualDesconto DECIMAL(5,2),
        ValorDesconto DECIMAL(18,2),
        ValorImposto DECIMAL(18,2),
        ValorLiquido DECIMAL(18,2)
    );

	-- INCLUSÃO DE ÍNDICE PARA MELHORAR A PERFORMANCE NO USO DO GROUP BY NO DELETE ABAIXO
	-- INDEX IX_#FechamentoFiscal CLUSTERED (ClienteID, ProdutoID, StatusCliente);
	-- A INCLUSÃO DO INDICE ACIMA NÃO FUNCIONOU, PRECISO ANALISAR.



	-- PASSEI TODOS OS CAMPOS ANTES DE INSERIR, 
	-- POIS SE FUTURAMENTE ALGUÉM INCLUI ALGUM CAMPO NO SELECT, ELE TBM SERÁ OBRIGADO A INSERIR NO INSERT INTO
	-- PARA QUE NÃO GRAVE INFOS ERRADAS NO CAMPO ERRADO
    INSERT INTO #FechamentoFiscal 
	(
		VendaID,
		ClienteID,
		NomeCliente,
		StatusCliente,
		DataVenda,
		StatusVenda,
		CanalID,
		NomeCanal,
		PercentualComissao,
		VendaItemID,
		ProdutoID,
		NomeProduto,
		CategoriaID,
		NomeCategoria,
		TaxaImpostoPadrao,
		Quantidade,
		ValorUnitario,
		ValorTotal,
		PercentualDesconto,
		ValorDesconto,
		ValorImposto,
		ValorLiquido
		)

        SELECT
            V.VendaID,
            V.ClienteID,
            C.Nome as NomeCliente,
            C.Status AS StatusCliente,
            V.DataVenda,
            V.Status AS StatusVenda,
            V.CanalID,
            CV.Nome AS NomeCanal,
            CV.PercentualComissao,
            VI.VendaItemID,
            VI.ProdutoID,
            P.Nome AS NomeProduto,
            P.CategoriaID,
            CAT.Nome AS NomeCategoria,
            CAT.TaxaImpostoPadrao,
            VI.Quantidade,
            VI.ValorUnitario,
            VI.ValorTotal,
            0.00 AS PercentualDesconto,
            0.00 AS ValorDesconto,
            0.00 AS ValorImposto,
            0.00 AS ValorLiquido
        FROM Vendas V 
        INNER JOIN VendasItens VI ON V.VendaID = VI.VendaID
        INNER JOIN Produtos P     ON VI.ProdutoID = P.ProdutoID
        INNER JOIN Categorias CAT ON P.CategoriaID = CAT.CategoriaID
        INNER JOIN Clientes C     ON V.ClienteID = C.ClienteID 
        INNER JOIN CanaisVenda CV ON V.CanalID = CV.CanalID
        WHERE V.DataVenda >= @DataInicio AND V.DataVenda < DATEADD(DAY,1,@DataFim)
			AND V.Status = @StatusFiltro;

		IF @SimularEstorno = 1
		BEGIN

		-- DELETA SOMENTE OS CLIENTES INATIVOS
		DELETE FROM #FechamentoFiscal 
		WHERE StatusCliente = 'Inativo';


		-- CRIA UMA TABELA TEMPORÁRIA PARA DEPOIS EXCLUIR SOMENTE OS CLIENTES QUE COMPRARAM MAIS DE 3 PRODUTOS
		CREATE TABLE #DeletarClientesxProdutosCTE
		(
	    ClienteID INT,
        ProdutoID INT,
        PRIMARY KEY CLUSTERED (ClienteID, ProdutoID)
		);


		INSERT INTO #DeletarClientesxProdutosCTE (ClienteID, ProdutoID)
		SELECT ClienteID, ProdutoID
		FROM #FechamentoFiscal
		GROUP BY ClienteID, ProdutoID
		HAVING SUM(Quantidade) > 3;


		DELETE F 
		FROM #FechamentoFiscal F
		INNER JOIN #DeletarClientesxProdutosCTE E ON (F.ClienteID = E.ClienteID) 
		AND F.ProdutoID = E.ProdutoID;


		DROP TABLE #DeletarClientesxProdutosCTE;
END;

---------------------------------------------------------------------------

    DECLARE 
        @VendaItemID INT,
        @ClienteID INT,
        @ProdutoID INT,
        @Categoria VARCHAR(100),
        @Canal VARCHAR(100),
        @Quantidade INT,
        @ValorUnitario DECIMAL(18,2),
        @TaxaImposto DECIMAL(9,4),
        @Desconto DECIMAL(5,2),
        @ValorTotal DECIMAL(18,2),
        @ValorDesconto DECIMAL(18,2),
        @ValorImposto DECIMAL(18,2),
        @ValorLiquido DECIMAL(18,2);

    DECLARE curItens CURSOR FOR
        SELECT 
            VendaItemID,
            ClienteID,
            ProdutoID,
            NomeCategoria,
            NomeCanal,
            Quantidade,
            ValorUnitario,
            TaxaImpostoPadrao
        FROM #FechamentoFiscal;

    OPEN curItens; -- INICIA O CURSOR


	-- INSERE OS DADOS ABAIXO NO SELECT ACIMA
    FETCH NEXT FROM curItens INTO -- AVANÇA SEMPRE PARA PRÓXIMA LINHA
        @VendaItemID,
        @ClienteID,
        @ProdutoID,
        @Categoria,
        @Canal,
        @Quantidade,
        @ValorUnitario,
        @TaxaImposto;

    WHILE @@FETCH_STATUS = 0 -- ENQUANTO HOUVER LINHAS A SEREM PROCESSADAS, REPITA O CÓDIGO

    BEGIN
        SELECT @Desconto = Desconto
        FROM dbo.fn_CalcularDescontoCliente_Atualizada(@ClienteID, GETDATE());

        SET @ValorTotal = @Quantidade * @ValorUnitario;
        SET @ValorDesconto = @ValorTotal * (@Desconto / 100.0);

        IF @Categoria = 'Eletrônicos' AND @Quantidade > 2
            SET @TaxaImposto = @TaxaImposto + 3.5;

        IF @Canal = 'App Mobile'
            SET @TaxaImposto = @TaxaImposto - 1;

        SET @ValorImposto = (@ValorTotal - @ValorDesconto) * (@TaxaImposto / 100.0);
        SET @ValorLiquido = @ValorTotal - @ValorDesconto + @ValorImposto;

---------------------------------------------------------------------------

        UPDATE #FechamentoFiscal
        SET 
            PercentualDesconto = @Desconto,
            ValorDesconto = @ValorDesconto,
            ValorImposto = @ValorImposto,
            ValorLiquido = @ValorLiquido
        WHERE VendaItemID = @VendaItemID;

        UPDATE VendasItens
        SET 
            PercentualDesconto = @Desconto,
            ValorDesconto = @ValorDesconto,
            ValorImposto = @ValorImposto,
            ValorLiquido = @ValorLiquido
        WHERE VendaItemID = @VendaItemID;



        IF @Categoria <> 'Livros'
        BEGIn
		    UPDATE Produtos
            SET Estoque = Estoque - @Quantidade
            WHERE ProdutoID = @ProdutoID;
        END; 

        FETCH NEXT FROM curItens INTO
            @VendaItemID,
            @ClienteID,
            @ProdutoID,
            @Categoria,
            @Canal,
            @Quantidade,
            @ValorUnitario,
            @TaxaImposto;
    END;

    CLOSE curItens;
    DEALLOCATE curItens;

    SELECT
        NomeCanal,
        NomeCategoria,
        COUNT(DISTINCT VendaID) AS TotalPedidos,
        SUM(Quantidade)         AS QuantidadeTotalItens,
        SUM(ValorTotal)         AS ReceitaBruta,
        SUM(ValorImposto)       AS TotalImposto,
        AVG(PercentualDesconto) AS DescontoMedioAplicado,
        SUM(ValorTotal) * AVG(PercentualComissao) / 100.0 AS ComissaoCanal
    FROM #FechamentoFiscal
    GROUP BY NomeCanal, NomeCategoria;

END;
GO