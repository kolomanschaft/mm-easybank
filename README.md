# mm-easybank
[MoneyMoney](https://moneymoney-app.com/) is a personal book keeping software for macOS. It is able to fetch bank statements from bank accounts automatically if the bank provides a HBCI/FinTS API. That includes most german banks.

For Banks who don't support HBCI/FinTS (which is most non-german banks) MoneyMoney provides a Lua scripting engine for building scraper extensions for web banking.

**mm-easybank** is such an extension for the austrian online bank **EasyBank**.

For security reasons MoneyMoney only lets you use signed extensions. The extension in `master` may not have a valid signature. Therefore you can only use it with Beta versions of MoneyMoney which allow you to deactivate code signature checks. If you don't want to use a Beta, check out the _releases_ section to find the latest signed release.

## Installation

### Install the extension

* Go to _releases_ and download the latest signed release of this extension
* Open MoneyMoney
* Select from the menu *Help > Show Database in Finder*
* Take the file `EasyBank.lua` from this Repo and place it in the `Extensions` folder
* A new account type _EasyBank_ should instantly show up in the _Add account_ dialog.

### Installing a development version

If you want to use the development version from `master` you have to use a Beta Version of MoneyMoney for reasons explained above. To get the latest Beta activate the flag _Participate in beta tests and display pre-release versions_ in the general preferences.

#### Deactivate Code Signatures

* Open MoneyMoney and open the preferences (`Cmd + ,`)
* In the _Extensions_ tab deactivate the flag _Verify digital signatures of extensions_