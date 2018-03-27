# mm-easybank
[MoneyMoney](https://moneymoney-app.com/) is a personal book keeping software for macOS. It is able to fetch bank statements from bank accounts automatically if the bank provides a HBCI/FinTS API. That includes most german banks.

For Banks who don't support HBCI/FinTS (which is most non-german banks) MoneyMoney provides a Lua scripting engine for building scraper extensions for web banking.

**mm-easybank** is such an extension for the austrian online bank **EasyBank**.

## Installation

* Open MoneyMoney and select the menu item *Help > Show database in Finder*
* Take the file `EasyBank.lua` from this Repo and place it in the `Extensions` folder
* A new account type *EasyBank* should instantly show up in the *Add account* dialog.