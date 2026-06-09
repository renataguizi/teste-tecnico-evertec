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
        NomeCliente VARCHAR(255),
        StatusCliente VARCHAR(255),
        DataVenda DATETIME,
        StatusVenda VARCHAR(255),
        CanalID INT,
        NomeCanal VARCHAR(255),
        PercentualComissao DECIMAL(18,2),
        VendaItemID INT,
        ProdutoID INT,
        NomeProduto VARCHAR(255),
        CategoriaID INT,
        NomeCategoria VARCHAR(255),
        TaxaImpostoPadrao DECIMAL(18,2),
        Quantidade INT,
        ValorUnitario DECIMAL(18,2),
        ValorTotal DECIMAL(18,2),
        PercentualDesconto DECIMAL(5,2),
        ValorDesconto DECIMAL(18,2),
        ValorImposto DECIMAL(18,2),
        ValorLiquido DECIMAL(18,2)
    );

	CREATE CLUSTERED INDEX IX_FechamentoFiscal ON #FechamentoFiscal
		(ClienteID,
		 ProdutoID);

	CREATE CLUSTERED INDEX IX_FechamentoFiscal ON #FechamentoFiscal
		(VendaItemID);


    INSERT INTO #FechamentoFiscal
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
            CAST(0 AS DECIMAL(5,2)) AS PercentualDesconto,
            CAST(0 AS DECIMAL(18,2)) AS ValorDesconto,
            CAST(0 AS DECIMAL(18,2)) AS ValorImposto,
            CAST(0 AS DECIMAL(18,2)) AS ValorLiquido
        FROM Vendas V 
        INNER JOIN VendasItens VI ON V.VendaID = VI.VendaID
        INNER JOIN Produtos P     ON VI.ProdutoID = P.ProdutoID
        INNER JOIN Categorias CAT ON P.CategoriaID = CAT.CategoriaID
        INNER JOIN Clientes C     ON V.ClienteID = C.ClienteID 
        INNER JOIN CanaisVenda CV ON V.CanalID = CV.CanalID
        WHERE V.DataVenda >= @DataInicio AND V.DataVenda < DATEADD(DAY,1,@DataFim)
			AND ( NULLIF(@StatusFiltro,'') IS NULL
					OR V.Status = @StatusFiltro);

    IF @SimularEstorno = 1
    BEGIN
        DELETE FROM #FechamentoFiscal
        WHERE StatusCliente = 'Inativo';

        DELETE F FROM #FechamentoFiscal F
        WHERE EXISTS
        (
            SELECT 1
            FROM #FechamentoFiscal X
            WHERE X.ClienteID = F.ClienteID
              AND X.ProdutoID = F.ProdutoID
            GROUP BY X.ClienteID, X.ProdutoID
            HAVING SUM(X.Quantidade) > 3
        );
    END;

    DECLARE 
        @VendaItemID INT,
        @ClienteID INT,
        @ProdutoID INT,
        @Categoria VARCHAR(100),
        @Canal VARCHAR(100),
        @Quantidade INT,
        @ValorUnitario DECIMAL(18,2),
        @TaxaImposto DECIMAL(18,2),
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

    OPEN curItens;

    FETCH NEXT FROM curItens INTO
        @VendaItemID,
        @ClienteID,
        @ProdutoID,
        @Categoria,
        @Canal,
        @Quantidade,
        @ValorUnitario,
        @TaxaImposto;

    WHILE @@FETCH_STATUS = 0
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
        BEGIN
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
        SUM(Quantidade) AS QuantidadeTotalItens,
        SUM(ValorTotal) AS ReceitaBruta,
        SUM(ValorImposto) AS TotalImposto,
        AVG(PercentualDesconto) AS DescontoMedioAplicado,
        SUM(ValorTotal) * AVG(PercentualComissao) / 100.0 AS ComissaoCanal
    FROM #FechamentoFiscal
    GROUP BY NomeCanal, NomeCategoria;

END;
GO