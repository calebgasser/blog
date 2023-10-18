# Source: https://elixirforum.com/t/flake-nix-phoenix-postgresql/52622
{
  description = "General Elixir Project Flake";
  #source: 20221130; https://github.com/toraritte/shell.nixes/blob/f9af46639a9bb5fb22705ebdfd25783866e22c0f/elixir-phoenix-postgres/shell.nix
  #source: 20221130; https://github.com/webuhu/elixir_nix_example

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # otherNixpkgs.url = "github:cw789/nixpkgs/erlang_update";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # outputs = { self, nixpkgs, otherNixpkgs, flake-utils }:
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # elixir_master_overlay = (self: super: {
        #   elixir = (super.beam.packagesWith super.erlang).elixir.override {
        #     src = builtins.fetchGit {
        #       url = "https://github.com/elixir-lang/elixir";
        #       ref = "master";
        #     };
        #     minimumOTPVersion = "25";
        #   };
        # });
        # pkgs = import <nixpkgs> { overlays = [ elixir_master_overlay ]; };

        # elixir_1_13_1_overlay = (self: super: {
        #   elixir_1_13 = super.elixir_1_13.override {
        #     version = "1.13.1";
        #     sha256 = "0z0b1w2vvw4vsnb99779c2jgn9bgslg7b1pmd9vlbv02nza9qj5p";
        #   };
        # });
        # pkgs = import <nixpkgs> { overlays = [ elixir_1_13_1_overlay ]; };


        # pkgs = nixpkgs.legacyPackages.${system};
        pkgs = import nixpkgs {
          inherit system;
        };
        # otherPkgs = otherNixpkgs.legacyPackages.${system};
        LANG = "C.UTF-8";
        # LANG= "en_US.UTF-8";
        root = ./.;


        # otherPkgs = import otherNixpkgs { system = "x86_64-linux"; };
        # myOverlay = self: super: { inherit (otherPkgs.legacyPackages) erlang }
        # pkgs = import nixpkgs { system = "x86_64-linux"; overlays = [ myOverlay ];  };

        # erlang = pkgs.beam.interpreters.erlangR25;
        # erlang = otherPkgs.beam.interpreters.erlangR25;
        elixir = pkgs.beam.packages.erlangR25.elixir_1_14;
        # elixir = otherPkgs.beam.packages.erlangR25.elixir_1_14;
        nodejs = pkgs.nodejs-18_x;
        postgresql = pkgs.postgresql_14;
      in
      {
        devShells.default = pkgs.mkShell {
          inherit LANG;
          # PGPORT = "5433"; # default 5432

          # enable IEx shell history
          ERL_AFLAGS = "-kernel shell_history enabled";
          # # In IEX: `open Enum.map`
          # ELIXIR_EDITOR = "code --goto __FILE__:__LINE__";

          ##########################################################
          # Without  this, almost  everything  fails with  locale issues  when
          # using `nix-shell --pure` (at least on NixOS).
          # See
          # + https://github.com/NixOS/nix/issues/318#issuecomment-52986702
          # + http://lists.linuxfromscratch.org/pipermail/lfs-support/2004-June/023900.html
          ##########################################################
          LOCALE_ARCHIVE = if pkgs.stdenv.isLinux then "${pkgs.glibcLocales}/lib/locale/locale-archive" else "";

          buildInputs = with pkgs; [
            elixir
            nodejs
            postgresql

            git
            elixir_ls
            # Show erlang version:
            # erl -eval '{ok, Version} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:fwrite(Version), halt().' -noshell
            # erlang
            pgcli
            glibcLocales
            gnumake
            gcc
            # readline
            # openssl
            # libxml2
            # curl
            # libiconv
            # yarn

            ## Deploy tools
            flyctl # fly.io
            # gigalixir

            # Used for frontend dependencies, you are free to use yarn2nix as well
            nodePackages.node2nix
            # Formatting .js file
            nodePackages.prettier

            nixpkgs-fmt
            # codespell --skip="./deps/*,./.git/*,./assets/*,./erl_crash.dump" -w
            codespell
            # dot -Tpng ecto_erd.dot -o erd.png
            graphviz

            (pkgs.writeShellScriptBin "pg-stop" ''
              pg_ctl -D $PGDATA -U postgres stop
            '')
            (pkgs.writeShellScriptBin "pg-reset" ''
              rm -rf $PGDATA
            '')
            (pkgs.writeShellScriptBin "pg-setup" ''
              ####################################################################
              # If database is not initialized (i.e., $PGDATA directory does not
              # exist), then set it up. Seems superfluous given the cleanup step
              # above, but handy when one gets to force reboot the iron.
              ####################################################################
              if ! test -d $PGDATA; then
                ######################################################
                # Init PostgreSQL
                ######################################################
                pg_ctl initdb -D  $PGDATA
                #### initdb --locale=C --encoding=UTF8 --auth-local=peer --auth-host=scram-sha-256 > /dev/null || exit
                # initdb --encoding=UTF8 --no-locale --no-instructions -U postgres
                ######################################################
                # PORT ALREADY IN USE
                ######################################################
                # If another `nix-shell` is  running with a PostgreSQL
                # instance,  the logs  will show  complaints that  the
                # default port 5432  is already in use.  Edit the line
                # below with  a different  port number,  uncomment it,
                # and try again.
                ######################################################
                if [[ "$PGPORT" ]]; then
                  sed -i "s|^#port.*$|port = $PGPORT|" $PGDATA/postgresql.conf
                fi
                echo "listen_addresses = ${"'"}${"'"}" >> $PGDATA/postgresql.conf
                echo "unix_socket_directories = '$PGDATA'" >> $PGDATA/postgresql.conf
                echo "CREATE USER postgres WITH PASSWORD 'postgres' CREATEDB SUPERUSER;" | postgres --single -E postgres
              fi
            '')
            (pkgs.writeShellScriptBin "pg-start" ''
              ## # Postgres Fallback using docker
              ## docker run -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:14

              [ ! -d $PGDATA ] && pg-setup

              ####################################################################
              # Start PostgreSQL
              # ==================================================================
              # Setting all  necessary configuration  options via  `pg_ctl` (which
              # is  basically  a wrapper  around  `postgres`)  instead of  editing
              # `postgresql.conf` directly with `sed`. See docs:
              #
              # + https://www.postgresql.org/docs/current/app-pg-ctl.html
              # + https://www.postgresql.org/docs/current/app-postgres.html
              #
              # See more on the caveats at
              # https://discourse.nixos.org/t/how-to-configure-postgresql-declaratively-nixos-and-non-nixos/4063/1
              # but recapping out of paranoia:
              #
              # > use `SHOW`  commands to  check the  options because  `postgres -C`
              # > "_returns values  from postgresql.conf_" (which is  not changed by
              # > supplying  the  configuration options  on  the  command line)  and
              # > "_it does  not reflect  parameters supplied  when the  cluster was
              # > started._"
              #
              # OPTION SUMMARY
              # --------------------------------------------------------------------
              #
              #  + `unix_socket_directories`
              #
              #    > PostgreSQL  will  attempt  to create  a  pidfile  in
              #    > `/run/postgresql` by default, but it will fail as it
              #    > doesn't exist. By  changing the configuration option
              #    > below, it will get created in $PGDATA.
              #
              #   + `listen_addresses`
              #
              #     > In   tandem  with   edits   in  `pg_hba.conf`   (see
              #     > `HOST_COMMON`  below), it  configures PostgreSQL  to
              #     > allow remote connections (otherwise only `localhost`
              #     > will get  authenticated and the rest  of the traffic
              #     > discarded).
              #     >
              #     > NOTE: the  edit  to  `pga_hba.conf`  needs  to  come
              #     >       **before**  `pg_ctl  start`  (or  the  service
              #     >       needs to be restarted otherwise), because then
              #     >       the changes are not being reloaded.
              #     >
              #     > More info  on setting up and  troubleshooting remote
              #     > PosgreSQL connections (these are  all mirrors of the
              #     > same text; again, paranoia):
              #     >
              #     >   + https://stackoverflow.com/questions/24504680/connect-to-postgres-server-on-google-compute-engine
              #     >   + https://stackoverflow.com/questions/47794979/connecting-to-postgres-server-on-google-compute-engine
              #     >   + https://medium.com/scientific-breakthrough-of-the-afternoon/configure-postgresql-to-allow-remote-connections-af5a1a392a38
              #     >   + https://gist.github.com/toraritte/f8c7fe001365c50294adfe8509080201#file-configure-postgres-to-allow-remote-connection-md
              HOST_COMMON="host\s\+all\s\+all"
              sed -i "s|^$HOST_COMMON.*127.*$|host all all 0.0.0.0/0 trust|" $PGDATA/pg_hba.conf
              sed -i "s|^$HOST_COMMON.*::1.*$|host all all ::/0 trust|"      $PGDATA/pg_hba.conf
              #  + `log*`
              #
              #    > Setting up basic logging,  to see remote connections
              #    > for example.
              #    >
              #    > See the docs for more:
              #    > https://www.postgresql.org/docs/current/runtime-config-logging.html

              pg_ctl                                                  \
                -D $PGDATA                                            \
                -l $PGDATA/postgres.log                               \
                -o "-c unix_socket_directories='$PGDATA'"             \
                -o "-c listen_addresses='*'"                          \
                -o "-c log_destination='stderr'"                      \
                -o "-c logging_collector=on"                          \
                -o "-c log_directory='log'"                           \
                -o "-c log_filename='postgresql-%Y-%m-%d_%H%M%S.log'" \
                -o "-c log_min_messages=info"                         \
                -o "-c log_min_error_statement=info"                  \
                -o "-c log_connections=on"                            \
                start
            '')
            (pkgs.writeShellScriptBin "pg-console" ''
              psql --host $PGDATA -U postgres
            '')

            (pkgs.writeShellScriptBin "pg-mix-setup" ''
              # ####/################################################################
              # # Install Node.js dependencies if not done yet.
              # ####################################################################
              # if test -d "$PWD/assets/" && ! test -d "$PWD/assets/node_modules/"; then
              #   (cd assets && npm install)
              # fi
              ####################################################################
              # If $MIX_HOME doesn't exist, set it up.
              ####################################################################
              if ! test -d $MIX_HOME; then
                ######################################################
                # ...  but first,  test whether  there is  a `_backup`
                # directory. Had issues with  installing Hex on NixOS,
                # and Hex and  Phoenix can be copied  from there, just
                # in case.
                ######################################################
                if test -d "$PWD/_backup"; then
                  cp -r _backup/.mix .nix-shell/
                else
                  ######################################################
                  # Install Hex and Phoenix via the network
                  ######################################################
                  yes | ${elixir}/bin/mix local.hex
                  # Install Phoenix
                  # yes | ${elixir}/bin/mix archive.install hex phx_new
                  #TODO:Go to stable whenever it's released
                  yes | ${elixir}/bin/mix archive.install hex phx_new 1.7.0-rc.0
                fi
              fi
              if test -f "mix.exs"; then
                # These are not in the  `if` section above, because of
                # the `hex` install glitch, it  could be that there is
                # already a `$MIX_HOME` folder. See 2019-08-05_0553
                ${elixir}/bin/mix deps.get
                ######################################################
                # `ecto.setup` is defined in `mix.exs` by default when
                # Phoenix  project  is  generated via  `mix  phx.new`.
                # It  does  `ecto.create`,   `ecto.migrate`,  and  run
                # `priv/seeds`.
                ######################################################
                ${elixir}/bin/mix ecto.setup
              fi
            '')

            (pkgs.writeShellScriptBin "check-formatted" ''
              cd ${root}

              echo " > CHECKING nix formatting"
              ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt *.nix --check
              echo " > CHECKING mix formatting"
              ${elixir}/bin/mix format --check-formatted
            '')
          ]
          ++ pkgs.lib.optional pkgs.stdenv.isLinux pkgs.libnotify # For ExUnit Notifier on Linux.
          ++ pkgs.lib.optional pkgs.stdenv.isLinux pkgs.inotify-tools # For file_system on Linux.
          ++ pkgs.lib.optional pkgs.stdenv.isDarwin pkgs.terminal-notifier # For ExUnit Notifier on macOS.
          ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
            # For file_system on macOS.
            CoreFoundation
            CoreServices
          ]);

          shellHook = ''
            if ! test -d .nix-shell; then
              mkdir .nix-shell
            fi

            export NIX_SHELL_DIR=$PWD/.nix-shell
            # Put the PostgreSQL databases in the project directory.
            export PGDATA=$NIX_SHELL_DIR/db
            # Put any Mix-related data in the project directory.
            export MIX_HOME=$NIX_SHELL_DIR/.mix
            export MIX_ARCHIVES=$MIX_HOME/archives
            export HEX_HOME=$NIX_SHELL_DIR/.hex

            export PATH=$MIX_HOME/bin:$PATH
            export PATH=$HEX_HOME/bin:$PATH
            export PATH=$MIX_HOME/escripts:$PATH
            export LIVEBOOK_HOME=$PWD

            ${elixir}/bin/mix --version
            ${elixir}/bin/iex --version
          '';
        };
      }
    );
}
