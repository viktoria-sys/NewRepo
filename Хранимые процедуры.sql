
USE ISERVDB;
GO

------------------------------------------------------------
-- 1) RPT_Subscrs_Debts_By_Term
-- Суммы начислений и остатки долга по трём возрастным группам
------------------------------------------------------------
IF OBJECT_ID('dbo.RPT_Subscrs_Debts_By_Term','P') IS NOT NULL
    DROP PROCEDURE dbo.RPT_Subscrs_Debts_By_Term;
GO
CREATE PROCEDURE dbo.RPT_Subscrs_Debts_By_Term
    @F_Subscr INT,
    @D_Date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.C_Number      AS [Номер ЛС],
        s.C_SecondName + ' ' + s.C_FirstName AS [ФИО],
        s.C_Address     AS [Адрес],
        b.C_Sale_Items  AS [Услуга],
        SUM(CASE WHEN DATEDIFF(DAY, b.D_Date, @D_Date) <= 30
                 THEN b.N_Amount ELSE 0 END)         AS [Нач. до 30 дней],
        SUM(CASE WHEN DATEDIFF(DAY, b.D_Date, @D_Date) <= 30
                 THEN b.N_Amount_Rest ELSE 0 END)    AS [Долг до 30 дней],
        SUM(CASE WHEN DATEDIFF(DAY, b.D_Date, @D_Date) BETWEEN 31 AND 180
                 THEN b.N_Amount ELSE 0 END)         AS [Нач. 31–180 дней],
        SUM(CASE WHEN DATEDIFF(DAY, b.D_Date, @D_Date) BETWEEN 31 AND 180
                 THEN b.N_Amount_Rest ELSE 0 END)    AS [Долг 31–180 дней],
        SUM(CASE WHEN DATEDIFF(DAY, b.D_Date, @D_Date) >= 181
                 THEN b.N_Amount ELSE 0 END)         AS [Нач. свыше 181 дня],
        SUM(CASE WHEN DATEDIFF(DAY, b.D_Date, @D_Date) >= 181
                 THEN b.N_Amount_Rest ELSE 0 END)    AS [Долг свыше 181 дня]
    FROM dbo.FD_Bills AS b
    JOIN dbo.SD_Subscrs AS s ON s.LINK = b.F_Subscr
    WHERE b.F_Subscr = @F_Subscr
      AND b.D_Date   <= @D_Date
    GROUP BY
        s.C_Number,
        s.C_SecondName + ' ' + s.C_FirstName,
        s.C_Address,
        b.C_Sale_Items;
END
GO


------------------------------------------------------------
-- 2) RPT_Subscrs_Debts_By_Year
-- По месяцам за год: с детализацией по услугам и без
------------------------------------------------------------
IF OBJECT_ID('dbo.RPT_Subscrs_Debts_By_Year','P') IS NOT NULL
    DROP PROCEDURE dbo.RPT_Subscrs_Debts_By_Year;
GO
CREATE PROCEDURE dbo.RPT_Subscrs_Debts_By_Year
    @F_Subscr INT,
    @N_Year   INT,
    @B_Detail BIT
AS
BEGIN
    SET NOCOUNT ON;

    IF @B_Detail = 0
    BEGIN
        SELECT
            s.C_Number AS [Номер ЛС],
            s.C_SecondName + ' ' + s.C_FirstName AS [ФИО],
            s.C_Address AS [Адрес],
            FORMAT(b.D_Date,'MM.yyyy') AS [Месяц],
            SUM(b.N_Amount)      AS [Сумма начисления],
            SUM(b.N_Amount_Rest) AS [Сумма долга]
        FROM dbo.FD_Bills AS b
        JOIN dbo.SD_Subscrs AS s ON b.F_Subscr = s.LINK
        WHERE b.F_Subscr = @F_Subscr
          AND YEAR(b.D_Date) = @N_Year
        GROUP BY
            s.C_Number,
            s.C_SecondName + ' ' + s.C_FirstName,
            s.C_Address,
            FORMAT(b.D_Date,'MM.yyyy')
        WITH ROLLUP
        HAVING GROUPING(FORMAT(b.D_Date,'MM.yyyy')) = 0;
    END
    ELSE
    BEGIN
        SELECT
            s.C_Number AS [Номер ЛС],
            s.C_SecondName + ' ' + s.C_FirstName AS [ФИО],
            s.C_Address AS [Адрес],
            FORMAT(b.D_Date,'MM.yyyy') AS [Месяц],
            b.C_Sale_Items             AS [Услуга],
            SUM(b.N_Amount)            AS [Сумма начисления],
            SUM(b.N_Amount_Rest)       AS [Сумма долга]
        FROM dbo.FD_Bills AS b
        JOIN dbo.SD_Subscrs AS s ON b.F_Subscr = s.LINK
        WHERE b.F_Subscr = @F_Subscr
          AND YEAR(b.D_Date) = @N_Year
        GROUP BY
            s.C_Number,
            s.C_SecondName + ' ' + s.C_FirstName,
            s.C_Address,
            FORMAT(b.D_Date,'MM.yyyy'),
            b.C_Sale_Items
        WITH ROLLUP
        HAVING 
            GROUPING(FORMAT(b.D_Date,'MM.yyyy')) = 0
         AND GROUPING(b.C_Sale_Items)         = 0;
    END
END
GO


------------------------------------------------------------
-- 3) RPT_Subscrs_Docs
-- Мероприятия по документу и всем родителям: не исполненные или исполненные до даты
------------------------------------------------------------
IF OBJECT_ID('dbo.RPT_Subscrs_Docs','P') IS NOT NULL
    DROP PROCEDURE dbo.RPT_Subscrs_Docs;
GO
CREATE PROCEDURE dbo.RPT_Subscrs_Docs
    @F_Docs INT,
    @D_Date DATE
AS
BEGIN
    SET NOCOUNT ON;

    WITH CTE_Docs AS (
        SELECT LINK, F_Subscr, C_Number, D_Date, F_Docs
        FROM dbo.DD_Docs
        WHERE LINK = @F_Docs
        UNION ALL
        SELECT d.LINK, d.F_Subscr, d.C_Number, d.D_Date, d.F_Docs
        FROM dbo.DD_Docs AS d
        JOIN CTE_Docs AS p ON d.LINK = p.F_Docs
    )
    SELECT
        s.C_Number                        AS [Номер ЛС],
        s.C_SecondName + ' ' + s.C_FirstName AS [ФИО],
        CONVERT(VARCHAR(10), s.D_BirthDate,104) AS [Дата рождения],
        c.C_Number                        AS [Номер документа],
        CONVERT(VARCHAR(10), c.D_Date,104)      AS [Дата документа],
        CASE WHEN DATEDIFF(YEAR, s.D_BirthDate, c.D_Date) >= 18 THEN 1 ELSE 0 END AS [Совершеннолетний],
        a.C_Name                          AS [Мероприятие],
        CONVERT(VARCHAR(10), a.D_NeedToDo_Date,104) AS [Плановая дата исполнения],
        CONVERT(VARCHAR(10), a.D_Done_Date,104)     AS [Дата исполнения],
        a.B_Done                          AS [Признак исполнено]
    FROM CTE_Docs AS c
    JOIN dbo.SD_Subscrs AS s ON s.LINK = c.F_Subscr
    JOIN dbo.DD_Docs_Assignments AS a ON a.F_Docs = c.LINK
    WHERE a.B_Done = 0 OR a.D_Done_Date <= @D_Date;
END
GO


------------------------------------------------------------
-- 4) RPT_Subscrs_Quantity
-- Текущее и предыдущее показание, расход, средний расход, тариф, сумма к оплате
------------------------------------------------------------
IF OBJECT_ID('dbo.RPT_Subscrs_Quantity','P') IS NOT NULL
    DROP PROCEDURE dbo.RPT_Subscrs_Quantity;
GO
CREATE PROCEDURE dbo.RPT_Subscrs_Quantity
    @F_Subscr INT,
    @D_Date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    WITH CTE_Read AS (
        SELECT
            d.LINK          AS DeviceID,
            d.C_Name        AS DeviceName,
            d.C_Serial_Number,
            d.C_Sale_Items  AS Service,
            d.D_Setup_Date,
            d.D_Replace_Date,
            r.LINK          AS ReadingID,
            r.D_Date        AS ReadDate,
            r.N_Value       AS ReadValue,
            ROW_NUMBER() OVER (
                PARTITION BY d.LINK
                ORDER BY ABS(DATEDIFF(DAY, r.D_Date, @D_Date))
            ) AS RN
        FROM dbo.ED_Devices d
        JOIN dbo.ED_Meter_Readings r
          ON r.F_Devices = d.LINK
        WHERE d.F_Subscr = @F_Subscr
    ),
    CTE_Current AS (
        SELECT *
        FROM CTE_Read
        WHERE RN = 1
    )

    SELECT
        s.C_Number                            AS [Номер ЛС],
        s.C_SecondName + ' ' + s.C_FirstName  AS [ФИО],
        c.DeviceName                          AS [ПУ],
        c.C_Serial_Number                     AS [Серийный номер],
        c.Service                             AS [Услуга],
        CONVERT(VARCHAR(10), c.D_Setup_Date,104)  AS [Дата установки],
        CONVERT(VARCHAR(10), c.D_Replace_Date,104)AS [Дата снятия],
        CONVERT(VARCHAR(10), c.ReadDate,104)       AS [Дата пкз.],
        c.ReadValue                             AS [Знач. пкз.],

        p.PrevValue      AS [Знач. пред. пкз.],
        CONVERT(VARCHAR(10), p.PrevDate,104) AS [Дата пред. пкз.],

        (c.ReadValue - p.PrevValue)          AS [Расход],

        AVG12.AvgConsumption                 AS [Средн. расход],

        t.N_Tariff                           AS [Тариф],

        (c.ReadValue - p.PrevValue) * t.N_Tariff AS [Сумма]
    FROM CTE_Current c
    OUTER APPLY (
        SELECT TOP 1
            pr.N_Value    AS PrevValue,
            pr.D_Date     AS PrevDate
        FROM dbo.ED_Meter_Readings pr
        WHERE pr.F_Devices = c.DeviceID
          AND pr.D_Date   < c.ReadDate
        ORDER BY pr.D_Date DESC
    ) p
    OUTER APPLY (
        SELECT TOP 1
            t.N_Tariff
        FROM dbo.ES_Tariff t
        WHERE t.C_Sale_Items = c.Service
          AND t.D_Date_Begin <= @D_Date
          AND (t.D_Date_End   >= @D_Date OR t.D_Date_End IS NULL)
        ORDER BY t.D_Date_Begin DESC
    ) t
    OUTER APPLY (
        SELECT
            SUM(r2.N_Value - r1.N_Value) / 12.0 AS AvgConsumption
        FROM dbo.ED_Meter_Readings r1
        JOIN dbo.ED_Meter_Readings r2
          ON r2.F_Devices = r1.F_Devices
         AND r2.D_Date BETWEEN DATEADD(MONTH,-12,@D_Date) AND @D_Date
         AND r2.LINK > r1.LINK
        WHERE r1.F_Devices = c.DeviceID
    ) AVG12
    JOIN dbo.SD_Subscrs s
      ON s.LINK = @F_Subscr;
END
GO
