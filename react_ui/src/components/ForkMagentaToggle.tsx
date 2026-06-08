/**
 * Fork toggle — same as @magenta-rt/common MagentaToggle but uses FORK_ACCENT.
 */

import Tooltip from '@mui/material/Tooltip';
import { InfoOutlined } from '@mui/icons-material';
import { FORK_ACCENT } from '../forkTheme';

interface ForkMagentaToggleProps {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  tooltip?: string;
  labelFontSize?: number;
}

const TRACK_W = 26;
const TRACK_H = 12;
const THUMB_SIZE = TRACK_H - 4;
const THUMB_PAD = 2;

export function ForkMagentaToggle({
  label,
  checked,
  onChange,
  tooltip,
  labelFontSize = 12,
}: ForkMagentaToggleProps) {
  const thumbLeft = checked ? TRACK_W - THUMB_SIZE - THUMB_PAD : THUMB_PAD;
  const accent = checked ? FORK_ACCENT : '#fff';

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', width: 'fit-content' }}>
      <div
        onClick={() => onChange(!checked)}
        className="magenta-toggle"
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
          cursor: 'pointer',
          width: 'fit-content',
        }}
      >
        <div
          style={{
            width: `${TRACK_W}px`,
            height: `${TRACK_H}px`,
            borderRadius: `${TRACK_H / 2}px`,
            outline: `2px solid ${checked ? FORK_ACCENT : '#fff'}`,
            position: 'relative',
            transition: 'background 0.15s ease, outline 0.15s ease',
            flexShrink: 0,
          }}
        >
          <div
            style={{
              position: 'absolute',
              top: `${THUMB_PAD}px`,
              left: `${thumbLeft}px`,
              width: `${THUMB_SIZE}px`,
              height: `${THUMB_SIZE}px`,
              borderRadius: '50%',
              background: accent,
              transition: 'left 0.15s ease, background 0.15s ease',
            }}
          />
        </div>

        <span
          className="magenta-toggle-label"
          style={{
            color: '#FFF',
            opacity: 0.7,
            fontFamily: "'Google Sans', sans-serif",
            fontSize: `${labelFontSize}px`,
            fontWeight: 500,
            lineHeight: 'normal',
            letterSpacing: '0.56px',
          }}
        >
          {label}
        </span>
      </div>

      {tooltip && (
        <Tooltip title={tooltip} placement="top" arrow>
          <InfoOutlined
            style={{
              fontSize: '13px',
              opacity: 0.3,
              cursor: 'help',
              color: '#FFF',
              flexShrink: 0,
            }}
          />
        </Tooltip>
      )}
    </div>
  );
}
