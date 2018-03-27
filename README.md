# mm-easybank
[MoneyMoney](https://moneymoney-app.com/) is a personal book keeping software for macOS. It is able to fetch bank statements from bank accounts automatically if the bank provides a HBCI/FinTS API. That includes most german banks.

For Banks who don't support HBCI/FinTS (which is most non-german banks) MoneyMoney provides a Lua scripting engine for building scraper extensions for web banking.

**mm-easybank** is such an extension for the austrian online bank **EasyBank**.

**NOTE: This extension can only be used in Beta versions of MoneyMoney**

For security reasons MoneyMoney only lets you use signed extensions. This extension **does not** have a signature. However you can stil use it by deactivating the signature check, but this can only be done in Beta-Versions of MoneyMoney.

## Installation

### Get a Beta Version

For reasons explained above this extension only works with Beta Versions of MoneyMoney. To get a Beta version activate the flag _Participate in beta tests and display pre-release versions_ in the general preferences.

### Install the extension

* Open MoneyMoney and open the preferences (`Cmd + ,`)
* In the _Extensions_ tab deactivate the flag _Verify digital signatures of extensions_
* Select from the menu *Help > Show Database in Finder*
* Take the file `EasyBank.lua` from this Repo and place it in the `Extensions` folder
* A new account type _EasyBank_ should instantly show up in the _Add account_ dialog.