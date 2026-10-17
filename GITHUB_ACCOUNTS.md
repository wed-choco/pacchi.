# GitHubアカウントの切り替え

GitHub公式CLIを `/Users/kii/.local/bin/gh` にインストール済みです。認証情報をここに貼り付けたり、Gitにコミットしたりする必要はありません。

## 初回だけ：2つのアカウントを登録

以下を実行し、ブラウザで希望するアカウントにログインして承認します。最初にwed-choco、次にwednesday13th1で行います。片方を追加しても、他方のCLI登録をログアウトする必要はありません。

```sh
/Users/kii/.local/bin/gh auth login --hostname github.com --git-protocol https --web
```

ブラウザが別のアカウントになっている場合、承認前に正しいアカウントへ切り替えてください。既存のwednesday13th1のmacOSキーチェーン資格情報は削除していません。

## 普段の切り替え

```sh
# wed-chocoを使う
/Users/kii/.local/bin/gh auth switch --hostname github.com --user wed-choco

# wednesday13th1を使う
/Users/kii/.local/bin/gh auth switch --hostname github.com --user wednesday13th1

# 現在の登録・認証状態を確認
/Users/kii/.local/bin/gh auth status
```

## このPacchi.リポジトリ

このリポジトリだけ、Gitのcredential helperをGitHub CLIに設定し、期待するユーザー名をwed-chocoに指定しています。CLIの有効アカウントが違う場合は、間違った認証を使わず失敗する設定です。ほかのリポジトリのキーチェーン設定は変更していません。

wed-chocoで認証後、以下でREADMEのコミットをプッシュできます。未コミットのアプリ実装はプッシュに含まれません。

```sh
/Users/kii/.local/bin/gh auth switch --hostname github.com --user wed-choco
git push -u origin main
```

別のリポジトリでもCLIによる切り替えを使う場合は、そのリポジトリ内で以下を一度設定します。usernameはそのリポジトリで使うアカウントに置き換えてください。

```sh
git config --local credential.https://github.com.username wednesday13th1
git config --local --replace-all credential.https://github.com.helper ''
git config --local --add credential.https://github.com.helper '!/Users/kii/.local/bin/gh auth git-credential'
```

`user.name`・`user.email`（コミット作者）と、プッシュの認証アカウントは別です。今回、作者情報は変更していません。

公式手順：https://cli.github.com/manual/gh_auth_switch
