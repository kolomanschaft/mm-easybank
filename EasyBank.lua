WebBanking        {
        version = 0.1,
        url = "https://ebanking.easybank.at/InternetBanking/InternetBanking?d=login&svc=EASYBANK&ui=html&lang=de",
        services = {"EasyBank"},
        description = "Extension für die österreichische Onine Bank EasyBank"
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
        local giroTable = mainPage:xpath("//*[@id='PART_CREDIT_CARD']")
        local giroAccounts = AccountsFromTable(giroTable, AccountTypeCreditCard)
        for i,acc in ipairs(giroAccounts) do
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
                        type = accountType
                }
        end

        return account
end


function RefreshAccount (account, since)
        -- This form is used to navigate to the first statements page
        local navForm = mainPage:xpath("//form[@name='financeOverviewForm']")
        navForm:xpath("input[@name='activeaccount']"):attr("value", account.accountNumber)
        navForm:xpath("input[@name='d']"):attr("value", "transactions")

        print("Fetching page 1")
        local statementsPage = HTML(connection:request(navForm:submit()))

        return RefreshAccountFromPage(account, since, statementsPage)
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


function TransactionFromTableRow (tableRow)
        local text = tableRow:xpath("td[4]"):text()
        local lines = {}
        local lineIndex = 0

        for line in text:gmatch("[^\r\n]+") do
            table.insert(lines, line)
            lineIndex = lineIndex + 1

            for part in line:gmatch("%S+") do 
                if isIban(part) then
                    accountNumber = part
                    purpose = table.concat(lines, "\r\n", 1, lineIndex - 1)

                    ibanPosStart = string.find(line, accountNumber)
                    ibanPosEnd = ibanPosStart + string.len(accountNumber)

                    accountName = string.sub(line, ibanPosEnd + 1)
                    if ibanPosStart > 1 then
                        bankCode = string.sub(line,0, ibanPosStart - 1)
                    end
                    lineIndexAccountName = lineIndex
                end
            end
        end

        if lineIndexAccountName == not nil then
            if lineIndex > lineIndexAccountName then
                accountName = accountName .. ' ' .. table.concat(lines, ' ', lineIndexAccountName + 1)
            end
        else
            purpose = text
        end

        local transaction = {
--              bankCode = bankCode,
                accountNumber = accountNumber,
                name = accountName,
                bankCode = bankCode,
                bookingDate = DateStringToTimestamp(tableRow:xpath("td[2]"):text()),
                purpose = purpose,
                amount = AmountStringToNumber(tableRow:xpath("td[10]"):text()),
                valueDate = DateStringToTimestamp(tableRow:xpath("td[6]"):text())
        }

        return transaction
end

local length=
{
  AL=28, AD=24, AT=20, AZ=28, BH=22, BE=16, BA=20, BR=29, BG=22, CR=21,
  HR=21, CY=28, CZ=24, DK=18, DO=28, EE=20, FO=18, FI=18, FR=27, GE=22,
  DE=22, GI=23, GR=27, GL=18, GT=28, HU=28, IS=26, IE=22, IL=23, IT=27,
  JO=30, KZ=20, KW=30, LV=21, LB=28, LI=21, LT=20, LU=20, MK=19, MT=31,
  MR=27, MU=30, MC=27, MD=24, ME=22, NL=18, NO=15, PK=24, PS=29, PL=28,
  PT=25, QA=29, RO=24, SM=27, SA=24, RS=22, SK=24, SI=19, ES=24, SE=24,
  CH=21, TN=24, TR=26, AE=23, GB=22, VG=24
}
 
function isIban(iban)
  iban=iban:gsub("%s","")
  local l=length[iban:sub(1,2)]
  if not l or l~=#iban or iban:match("[^%d%u]") then
    return false -- invalid character, country code or length
  end
  local mod=0
  local rotated=iban:sub(5)..iban:sub(1,4)
  for c in rotated:gmatch(".") do
    mod=(mod..tonumber(c,36)) % 97
  end
  return mod==1
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