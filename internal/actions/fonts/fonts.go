package fonts

// Font represents a Nerd Font available for install/remove.
type Font struct {
	Name string // oh-my-posh install name (e.g. "CascadiaCode")
}

// fontFamilyOverride maps oh-my-posh names to the actual Nerd Font family prefix
// when it differs from the oh-my-posh name.
var fontFamilyOverride = map[string]string{
	"CascadiaCode": "CaskaydiaCove",
	"CascadiaMono": "CaskaydiaMono",
}

// Family returns the Alacritty-compatible font family name (Nerd Fonts v3).
func (f Font) Family() string {
	prefix := f.Name
	if p, ok := fontFamilyOverride[f.Name]; ok {
		prefix = p
	}
	return prefix + " Nerd Font Mono"
}

// All returns the full list of Nerd Fonts available via oh-my-posh.
func All() []Font {
	return []Font{
		{Name: "0xProto"},
		{Name: "3270"},
		{Name: "AdwaitaMono"},
		{Name: "Agave"},
		{Name: "AnonymousPro"},
		{Name: "Arimo"},
		{Name: "AtkinsonHyperlegibleMono"},
		{Name: "AurulentSansMono"},
		{Name: "BigBlueTerminal"},
		{Name: "BitstreamVeraSansMono"},
		{Name: "CascadiaCode"},
		{Name: "CascadiaMono"},
		{Name: "CodeNewRoman"},
		{Name: "ComicShannsMono"},
		{Name: "CommitMono"},
		{Name: "Cousine"},
		{Name: "D2Coding"},
		{Name: "DaddyTimeMono"},
		{Name: "DejaVuSansMono"},
		{Name: "DepartureMono"},
		{Name: "DroidSansMono"},
		{Name: "EnvyCodeR"},
		{Name: "FantasqueSansMono"},
		{Name: "FiraCode"},
		{Name: "FiraMono"},
		{Name: "GeistMono"},
		{Name: "Go-Mono"},
		{Name: "Gohu"},
		{Name: "Hack"},
		{Name: "Hasklig"},
		{Name: "HeavyData"},
		{Name: "Hermit"},
		{Name: "IBMPlexMono"},
		{Name: "Inconsolata"},
		{Name: "InconsolataGo"},
		{Name: "InconsolataLGC"},
		{Name: "IntelOneMono"},
		{Name: "Iosevka"},
		{Name: "IosevkaTerm"},
		{Name: "IosevkaTermSlab"},
		{Name: "JetBrainsMono"},
		{Name: "Lekton"},
		{Name: "LiberationMono"},
		{Name: "Lilex"},
		{Name: "MPlus"},
		{Name: "MartianMono"},
		{Name: "Meslo"},
		{Name: "Monaspace"},
		{Name: "Monofur"},
		{Name: "Monoid"},
		{Name: "Mononoki"},
		{Name: "Noto"},
		{Name: "OpenDyslexic"},
		{Name: "Overpass"},
		{Name: "ProFont"},
		{Name: "ProggyClean"},
		{Name: "Recursive"},
		{Name: "RobotoMono"},
		{Name: "ShareTechMono"},
		{Name: "SourceCodePro"},
		{Name: "SpaceMono"},
		{Name: "Terminus"},
		{Name: "Tinos"},
		{Name: "Ubuntu"},
		{Name: "UbuntuMono"},
		{Name: "UbuntuSans"},
		{Name: "VictorMono"},
		{Name: "ZedMono"},
		{Name: "iA-Writer"},
	}
}
