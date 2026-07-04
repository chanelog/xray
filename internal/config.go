package internal

type Config struct {
	Listen  string
	Backend string
	Path    string
}

func DefaultConfig() Config {

	return Config{
		Listen:  ":700",
		Backend: "127.0.0.1:22",
		Path:    "/ssh-ws",
	}

}
