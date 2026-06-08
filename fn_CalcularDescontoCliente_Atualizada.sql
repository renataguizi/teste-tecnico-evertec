-- DROP FUNCTION IF EXISTS dbo.fn_CalcularDescontoCliente_Atualizada;

CREATE FUNCTION dbo.fn_CalcularDescontoCliente_Atualizada
(
    @ClienteID INT,
    @DataAnalise DATETIME
)
 RETURNS @Resultado TABLE
(
    ClienteID INT,
    TotalComprado DECIMAL(18,2),
    QtdCategorias INT,
    UltimaCompra DATETIME,
    Desconto DECIMAL(5,2)
)
AS
BEGIN
    DECLARE @TotalComprado DECIMAL(18,2);
    DECLARE @QtdCategorias INT;
    DECLARE @UltimaCompra DATETIME;
    DECLARE @Desconto DECIMAL(5,2);
    DECLARE @ClienteAtivo BIT;
    DECLARE @QtdComprasCliente INT;
    DECLARE @QtdComprasRecentes INT;
    DECLARE @QtdCancelamentosRecentes INT;
    DECLARE @QtdProdutosDistintos INT;

    SET @Desconto = 0;
    SET @TotalComprado = 0;
    SET @QtdCategorias = 0;
    SET @QtdComprasCliente = 0;

	SELECT
		@ClienteAtivo = CASE WHEN EXISTS (SELECT 1 FROM Clientes C WHERE C.ClienteID = @ClienteID AND C.Status <> 'Bloqueado') 
							 THEN 1 ELSE 0 END;

    SELECT 
		@QtdComprasCliente = COUNT(DISTINCT V.VendaID),
        @TotalComprado = SUM(ISNULL(VI.Quantidade, 0) * ISNULL(VI.ValorUnitario, 0)),
        @QtdCategorias = COUNT(DISTINCT P.CategoriaID)
    FROM Vendas V
    INNER JOIN VendasItens VI ON (V.VendaID = VI.VendaID)
    INNER JOIN Produtos P     ON (VI.ProdutoID = P.ProdutoID)
    WHERE V.ClienteID = @ClienteID
      AND V.Status = 'Concluida'
      AND V.DataVenda < DATEADD(DAY, 1, CAST(@DataAnalise AS DATE));

	IF ISNULL(@TotalComprado, 0) > 10000
        SET @Desconto += 10;
    ELSE IF ISNULL(@TotalComprado, 0) BETWEEN 5000 AND 10000
        SET @Desconto += 5;

    IF ISNULL(@QtdCategorias, 0) >= 3
        SET @Desconto += 5;

    SELECT 
        @QtdProdutosDistintos = COUNT(DISTINCT VI.ProdutoID)
    FROM Vendas V
    INNER JOIN VendasItens VI ON (V.VendaID = VI.VendaID)
    WHERE V.ClienteID = @ClienteID
      AND V.Status = 'Concluida'
      AND V.DataVenda >= DATEADD(DAY, -365, @DataAnalise);

    IF ISNULL(@QtdProdutosDistintos, 0) > 20
        SET @Desconto += 0.50;

    SELECT 
        @UltimaCompra = MAX(V.DataVenda)
    FROM Vendas V
    WHERE V.ClienteID = @ClienteID
      AND V.Status = 'Concluida';

    IF @UltimaCompra IS NULL
       OR DATEDIFF(DAY, @UltimaCompra, @DataAnalise) > 180
        SET @Desconto -= 2;

    SELECT 
        @QtdComprasRecentes = COUNT(*)
    FROM Vendas V
    WHERE V.ClienteID = @ClienteID
      AND V.Status = 'Concluida'
      AND V.DataVenda >= DATEADD(DAY, -30, @DataAnalise)
      AND V.DataVenda < DATEADD(DAY, 1, CAST(@DataAnalise AS DATE));

    IF ISNULL(@QtdComprasRecentes, 0) >= 2
        SET @Desconto += 0.50;

    SELECT
        @QtdCancelamentosRecentes = COUNT(*)
    FROM Vendas V
    WHERE V.ClienteID = @ClienteID
      AND V.Status = 'Cancelada'
      AND V.DataVenda >= DATEADD(DAY, -90, @DataAnalise);

    IF ISNULL(@QtdCancelamentosRecentes, 0) > 0
        SET @Desconto -= 0.50;

    IF ISNULL(@QtdComprasCliente, 0) = 0
        SET @Desconto = 0;

    IF ISNULL(@ClienteAtivo, 0) = 0
        SET @Desconto = 0;

    IF @Desconto < 0
        SET @Desconto = 0;

    INSERT INTO @Resultado
    (
        ClienteID,
        TotalComprado,
        QtdCategorias,
        UltimaCompra,
        Desconto
    )
    VALUES
    (
        @ClienteID,
        ISNULL(@TotalComprado, 0),
        ISNULL(@QtdCategorias, 0),
        @UltimaCompra,
        ISNULL(@Desconto, 0)
    );

    RETURN;
END;
GO