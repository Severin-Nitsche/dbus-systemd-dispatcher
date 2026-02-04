package main

import (
  "flag"
  "context"
  "fmt"
  "log"
  "plugin"

  "github.com/coreos/go-systemd/v22/daemon"
  systemd "github.com/coreos/go-systemd/v22/dbus"
  dbus "github.com/godbus/dbus/v5"

  "github.com/ilyakaznacheev/cleanenv"
)

// Starts/Stops a systemd unit and blocks until the job is completed.
func HandleSystemdUnit(unitName string, start bool, system bool) error {
  var conn *systemd.Conn
  var err error

  if system {
    conn, err = systemd.NewSystemConnectionContext(context.Background())
  } else {
    conn, err = systemd.NewUserConnectionContext(context.Background())
  }

  if err != nil {
    return fmt.Errorf("failed to connect to systemd session (system: %v): %v", system, err)
  }

  ch := make(chan string, 1)

  if start {
    _, err = conn.StartUnitContext(context.Background(), unitName, "replace", ch)
  } else {
    _, err = conn.StopUnitContext(context.Background(), unitName, "replace", ch)
  }
  if err != nil {
    return fmt.Errorf("failed to handle unit (start: %v): %v", start, err)
  }

  result := <-ch
  if result == "done" {
    log.Printf("Handled systemd unit: %v (system: %v, start: %v)", unitName, system, start)
  } else {
    return fmt.Errorf("failed to handle unit %v (system: %v, start: %v): %v", unitName, system, start, result)
  }

  return nil
}

type Hardcode = func() (
  func(), 
  func(*dbus.Conn, *dbus.Signal) bool, 
  func(), 
  func(),
)

func ListenFor(
  target string, 
  toggle bool, 
  start bool, 
  system bool, 
  hardcode Hardcode, 
  options ...dbus.MatchOption,
) {
  conn, err := dbus.ConnectSystemBus()
  if err != nil {
    log.Fatalln("Could not connect to the system D-Bus", err)
  }

  err = conn.AddMatchSignal(options...)
  if err != nil {
    log.Fatalf("Failed to listen for %v signals: %v", target, err)
  }

  init, verify, before, after := hardcode();

  c := make(chan *dbus.Signal, 10)

  // Hardcode: Initialize logind for sleep.target
  init()


  waitFor := func (start bool) {
    for {
      v := <-c

      // Hardcode: verify user session for (un)lock.target
      // Hardcode: verify want==got for sleep.target
      if verify(conn, v) {
	break
      }
    }

    err = HandleSystemdUnit(target, start, system)
    if err != nil {
      log.Println("Error handling target:", target, err)
    }
  }

  go func() {
    for {
      // Hardcode: Inhibit Sleep for sleep.target
      before()

      waitFor(start)

      if !toggle {
        continue
      }

      // Hardcode: Uninhibit Sleep for sleep.target
      after()

      waitFor(!start)

    }
  }()

  conn.Signal(c)
  log.Printf("Listening for %v signals", target);
}

type Config struct {
  Targets map[string]struct {
    Dlib string `yaml:"dlib"`
    Toggle bool `yaml:"toggle"`
    Start bool `yaml:"start"`
    System bool `yaml:"system"`
    MatchOptions map[string]string `yaml:"dbus"`
  } `yaml:"targets"`
}

type ConfigPaths struct {
  ConfigDirs []string `env:"XDG_CONFIG_DIRS" env-separator:":" env-default:"/etc/xdg"`
  ConfigHome string `env:"XDG_CONFIG_HOME" env-default:""`
  Home []string `env:"HOME"`
}

func searchPaths[T any](override bool, value *T, subdir string, file string, merge func(string, any) error, paths ...string) {
  ok := false
  f := -1
  offset := len(paths) - 1
  if override {
    f = 1
    offset = 0
  }
  for i := 0; i < len(paths); i++ {
    path := paths[f*i+offset]
    file := fmt.Sprintf("%v/%v/%v",path,subdir,file)
    err := merge(file, value)
    if err == nil {
      ok = true // We found a valid file
      if override {
	return
      }
    }
  }

  if !ok {
    log.Fatalln("Failed to locate file:", file)
  }
}

func parseConfig() (Config, ConfigPaths) {
  var cfg Config
  var paths ConfigPaths

  // Check if there is a command-line argument set
  configFile := flag.String("config", "config.yml", "The name of the configuration file.")
  configPath := flag.String("search-path", "environment", "Additional configuration search path.")
  override := flag.Bool("override", false, "Apply the most important config file instead of merging.")
  flag.Parse()

  err := cleanenv.ReadEnv(&paths)
  if err != nil && *configPath == "environment" {
    log.Fatalln("Failed to read environment paths:", err)
  }

  // Ensure that $XDG_CONFIG_HOME is well formed
  if paths.ConfigHome == "" {
    paths.ConfigHome = fmt.Sprintf("%v/.config",paths.Home)
  }

  dirs := make([]string, len(paths.ConfigDirs)+2)
  copy(dirs[2:], paths.ConfigDirs)
  dirs[1] = paths.ConfigHome
  dirs[0] = *configPath
  if *configPath == "environment" {
    dirs = dirs[1:]
  }
  paths.ConfigDirs = dirs

  searchPaths(*override, &cfg, "dbus-systemd-dispatcher", *configFile, cleanenv.ReadConfig, paths.ConfigDirs...)

  return cfg, paths
}

func main() {
  log.SetFlags(log.Lshortfile)

  cfg,paths := parseConfig()

  for name, target := range cfg.Targets {
    // Convert the matchOptions map to []MatchOption
    matchOptions := make([]dbus.MatchOption, 0, len(target.MatchOptions))
    for key, value := range target.MatchOptions {
      matchOptions = append(matchOptions, dbus.WithMatchOption(key, value))
    }
    
    // Load dynamic library
    dload := func(path string, lib any) error {
      var err error
      dlib := lib.(**plugin.Plugin)
      *dlib, err = plugin.Open(path)
      return err
    }

    var dlib *plugin.Plugin 
    searchPaths(true, &dlib, "dbus-systemd-dispatcher", target.Dlib, dload, paths.ConfigDirs...)

    symbol, err := dlib.Lookup("Hardcode")
    if err != nil {
      log.Fatalf("Failed to locate symbol 'Hardcode' in dynamic library %v for target %v: %v", target.Dlib, name, err)
    }

    hardcode, ok := symbol.(Hardcode)
    if !ok {
      log.Fatalf("Unexpected signature for symbol 'Hardcode' in dynamic library %v for target %v", target.Dlib, name)
    }

    // Dispatch Listener
    ListenFor(
      name,
      target.Toggle,
      target.Start,
      target.System,
      hardcode,
      matchOptions...,
    )
  }

  log.Println("Initialization complete.")

  sent, err := daemon.SdNotify(true, daemon.SdNotifyReady)
  if !sent {
    log.Println("Couldn't call sd_notify. Not running via systemd?")
  }
  if err != nil {
    log.Println("Call to sd_notify failed:", err)
  }

  select {}
}
