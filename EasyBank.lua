WebBanking        {
        version = 0.1,
        url = "https://ebanking.easybank.at/InternetBanking/InternetBanking?d=login&svc=EASYBANK&ui=html&lang=de",
        services = {"EasyBank"},
        description = "Extension für die österreichische Online Bank EasyBank"
}

local mainPage = nil
local connection = nil
local easyBankBic = "EASYATW1"
local logoutUrl = "https://ebanking.easybank.at/InternetBanking/InternetBanking/?d=logoutredirect&isgetprg=true"


function SupportsBank(protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "EasyBank"
end


function InitializeSession (protocol, bankCode, username, username2, password, username3)
        connection = Connection()

        print("Loading login page: " .. url)

        local loginPage = HTML(connection:get(url))

        loginPage:xpath("//*[@id='lof5']"):attr("value", username)
        loginPage:xpath("//*[@id='lof9']"):attr("value", password)

        print("Logging in...")

        mainPage = HTML(connection:request(loginPage:xpath("//*[@id='form']"):submit()))

        -- Check if we are actually logged in
        local financeOverview = mainPage:xpath("//*[@id='financeoverview']")
        if financeOverview:length() == 0 then
                local errorElement = mainPage:xpath("//*[@id='error_part_text']")
                print("Login error: " .. errorElement:text())
                return errorElement:text()
        end

        print("Login successful!")

        return nil
end


function ListAccounts (knownAccounts)
        local accounts = {}

        -- Add Giro Accounts
        local giroTable = mainPage:xpath("//*[@id='PART_GIRO_EUR']")
        local giroAccounts = AccountsFromTable(giroTable, AccountTypeGiro)
        for i,acc in ipairs(giroAccounts) do
                table.insert(accounts, acc)
        end

        -- Add Credit Card Accounts
        local creditCardTable = mainPage:xpath("//*[@id='PART_CREDIT_CARD']")
        local creditCardAccounts = AccountsFromTable(creditCardTable, AccountTypeCreditCard)
        for i,acc in ipairs(creditCardAccounts) do
                table.insert(accounts, acc)
        end

        -- Add Savings Accounts
        local savingsTable = mainPage:xpath("//*[@id='PART_SAVINGS']")
        local savingsAccounts = AccountsFromTable(savingsTable, AccountTypeSavings)
        for i, acc in ipairs(savingsAccounts) do
                table.insert(accounts, acc)
        end

        -- Add Portfolio Accounts
        local portfolioTable = mainPage:xpath("//*[@id='PART_BROKERAGE']")
        local portfolioAccounts = AccountsFromTable(portfolioTable, AccountTypePortfolio)
        for i, acc in ipairs(portfolioAccounts) do
                table.insert(accounts, acc)
        end

        return accounts
end


function AccountsFromTable (tableElement, accountType)
        local accounts = {}
        local tableRows = tableElement:xpath("div[2]/div[1]/div/div/table"):children()

        tableRows:each(
                function (index, element)
                        local account = AccountFromTableRow(element, accountType)
                        if account ~= nil then
                                table.insert(accounts, account)
                        end
                end
        )

        return accounts
end


function AccountFromTableRow(tableRowElement, accountType)
        local account = nil
        local accountNumber = tableRowElement:attr("id")

        if accountNumber:len() > 0 then
                local myIban = tableRowElement:xpath("td[2]/a"):text()
                local myName = tableRowElement:xpath("td[4]"):text()
                local myOwner = tableRowElement:xpath("td[6]"):text()
                local description = tableRowElement:xpath("td[8]"):text()

                if description:len() > 0 then
                        myName = description
                end

                account = {
                        name = myName,
                        accountNumber = accountNumber,
                        owner = myOwner,
                        currency = "EUR",
                        iban = myIban,
                        bic = easyBankBic,
                        type = accountType,
                        portfolio = accountType == AccountTypePortfolio
                }
        end

        return account
end


function RefreshAccount (account, since)
        -- This form is used to navigate to the first statements page
        local navForm = mainPage:xpath("//form[@name='financeOverviewForm']")
        navForm:xpath("input[@name='activeaccount']"):attr("value", account.accountNumber)
        local d = "transactions"
        if account.type == AccountTypePortfolio then
                d = "brokerageaccountstatementlist"
        end
        navForm:xpath("input[@name='d']"):attr("value", d)
        print("Fetching page 1")
        local statementsPage = HTML(connection:request(navForm:submit()))

        if account.type == AccountTypePortfolio then
                return RefreshBrokerAccountFromPage(account, since, statementsPage)
        else
                return RefreshAccountFromPage(account, since, statementsPage)
        end
end

function RefreshBrokerAccountFromPage(account, since, statementsPage)
        -- These rows contain the statements
        local tableRows = statementsPage:xpath("//*[@id='depotNotionTable']/tbody"):children()

        -- TODO: support multiple pages

        local securities = {}

        tableRows:each(
                function(index, element)
                        if string.len(element:text()) > 0 then
                                local security = SecurityFromTableRow(element)
                                table.insert(securities, security)
                        end
                end
        )

        return {securities = securities}
end

function RefreshAccountFromPage (account, since, statementsPage)
        -- These rows contain the statements
        local tableRows = statementsPage:xpath("//table[@id='exchange-details']/tbody"):children()

        -- The search form is used to navigate between pages
        local searchForm = statementsPage:xpath("//form[@name='transactionSearchForm']")

        local balance = AmountStringToNumber(searchForm:xpath("div[1]/div[2]/div[2]/span[1]"):text():gsub("%sEUR",""))
        local page = tonumber(searchForm:xpath("input[@name='pagenumber']"):attr("value"))

        -- Credit card dept is shown as positive number
        if account.type == AccountTypeCreditCard then
                balance = -balance
        end

        -- If the "Next" button is active there is a next page
        local nextPage = statementsPage:xpath("//div[@id='print']/div[7]/div/div/a"):attr("onclick"):len() > 0

        local transactions = {}

        print("--------- TRANSACTIONS PAGE " .. page .. " ---------")
        tableRows:each(
                function (index, element)
                        local transation = TransactionFromTableRow(element)
                        print(TimestampToDateString(transation.bookingDate) .. " -- " .. transation.amount .. " -- " .. transation.purpose)
                        if transation.bookingDate >= since then
                                table.insert(transactions, transation)
                        else
                                nextPage = false
                                return false
                        end
                end
        )
        print("----------------------------------------------------")

        if nextPage == true then
                -- Prepare the search form and fetch the next page
                page = page + 1
                print("Fetching page " .. page)
                searchForm:xpath("input[@name='pagenumber']"):attr("value", tostring(page))
                searchForm:xpath("//*[@id='account-entry-switcher']"):select("30")

                local nextStatementsPage = HTML(connection:request(searchForm:submit()))

                -- Recursively calling myself with the next page
                nextPageResults = RefreshAccountFromPage(account, since, nextStatementsPage)

                for i, transaction in ipairs(nextPageResults.transactions) do
                        table.insert(transactions, transaction)
                end
        else
                print("Finished fetching transactions")
        end

        return {balance=balance, transactions = transactions}
end

function SecurityFromTableRow(tableRow)
        local currency
        local purchasePrice = AmountStringToNumber(tableRow:xpath("td[10]/text()[1]"):text():gsub("%sEUR", ""))
        local quantity = AmountStringToNumber(tableRow:xpath("td[5]/span/a/text()"):text():gsub("%sEUR", ""))
        if quantity then
                currency = "EUR"
                purchasePrice = purchasePrice * 100
        else
                quantity = AmountStringToNumber(tableRow:xpath("td[5]/span/a/text()"):text():gsub("%Stk.", ""))
        end
        purchasePrice = purchasePrice / quantity

        local security = {
                isin = tableRow:xpath("td[2]/text()[1]"):text(),
                name = tableRow:xpath("td[4]/text()[1]"):text(),
                market = tableRow:xpath("td[4]/text()[2]"):text(),
                amount = AmountStringToNumber(tableRow:xpath("td[8]"):text():gsub("%sEUR", "")),
                currency = currency,
                quantity = quantity,
                purchasePrice = purchasePrice
        }

        return security
end

function TransactionFromTableRow (tableRow)
        local transaction = {
                bookingDate = DateStringToTimestamp(tableRow:xpath("td[2]"):text()),
                purpose = tableRow:xpath("td[4]"):text(),
                amount = AmountStringToNumber(tableRow:xpath("td[10]"):text()),
                valueDate = DateStringToTimestamp(tableRow:xpath("td[6]"):text())
        }

        return transaction
end


function DateStringToTimestamp(dateString)
    local dayStr, monthStr, yearStr = string.match(dateString, "(%d%d).(%d%d).(%d%d%d%d)")

    return os.time({
        year = tonumber(yearStr),
        month = tonumber(monthStr),
        day = tonumber(dayStr)
    })
end


function TimestampToDateString(timestamp)
        return os.date("%d.%m.%Y", timestamp)
end


function AmountStringToNumber(amountString)
        resultStr = string.gsub(amountString, "%.", "")
        resultStr = string.gsub(resultStr, ",", ".")
        return tonumber(resultStr)
end


function EndSession()
        print("Logging out...")
        connection:get(logoutUrl)
end