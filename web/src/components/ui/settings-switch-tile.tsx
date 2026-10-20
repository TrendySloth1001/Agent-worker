import { SettingsTile, type SettingsTileProps } from "./settings-tile";
import { Switch } from "./switch";

interface SettingsSwitchTileProps extends Omit<
  SettingsTileProps,
  "trailing" | "chevron" | "onClick"
> {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
}

export function SettingsSwitchTile({
  checked,
  onCheckedChange,
  title,
  ...rest
}: SettingsSwitchTileProps) {
  return (
    <SettingsTile
      {...rest}
      title={title}
      onClick={() => onCheckedChange(!checked)}
      trailing={
        <Switch
          checked={checked}
          onCheckedChange={onCheckedChange}
          aria-label={title}
          tabIndex={-1}
          onClick={(e) => e.stopPropagation()}
        />
      }
    />
  );
}
