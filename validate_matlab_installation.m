function results = validate_matlab_installation()
%VALIDATE_MATLAB_INSTALLATION Check that required MATLAB products/add-ons are installed.
%
%   results = VALIDATE_MATLAB_INSTALLATION() verifies that the following
%   products, toolboxes, support packages and add-ons are installed in the
%   current MATLAB installation:
%
%       - MATLAB Coder
%       - Simulink Coder
%       - Embedded Coder
%       - Stateflow
%       - Simscape
%       - Simscape Electrical
%       - AUTOSAR Blockset
%       - MinGW-w64 C/C++ Compiler
%       - NXP Model-Based Design Toolbox for S32K3xx (MBDT for S32K3)
%       - Embedded Coder Support Package for ARM Cortex-M (Cortex-M target)
%       - NXP FreeMASTER (standalone Windows application)
%
%   The function prints a PASS/FAIL report to the Command Window and returns
%   a table summarizing the result for every requirement. If one or more
%   requirements are not satisfied, the function throws an error so it can be
%   used in an automated/CI setting (the error is raised only after the full
%   report is printed).
%
%   Detection strategy
%   ------------------
%   * Installed products are read with VER (Name field).
%   * Installed support packages / add-ons are read with
%     MATLAB.ADDONS.INSTALLEDADDONS (Name column).
%   * The MinGW compiler is additionally probed via
%     MEX.GETCOMPILERCONFIGURATIONS so it is detected even when it is
%     registered only as a compiler and not as an add-on.
%   * NXP FreeMASTER is a standalone Windows application (not a MATLAB
%     product), so it is detected by scanning the Windows "Uninstall"
%     registry keys for a DisplayName that contains "FreeMASTER". On
%     non-Windows platforms this check is reported as not applicable.
%   * Matching is case-insensitive and uses regular-expression patterns so
%     that minor naming/version differences between releases still match.
%
%   Example:
%       results = validate_matlab_installation();
%
%   See also VER, MATLAB.ADDONS.INSTALLEDADDONS, MEX.GETCOMPILERCONFIGURATIONS.

    % ---------------------------------------------------------------------
    % 1. Define the requirements.
    %    Each requirement has a friendly display name and one or more
    %    case-insensitive regular-expression patterns. A requirement is
    %    considered satisfied if ANY of its patterns matches ANY installed
    %    product or add-on name.
    % ---------------------------------------------------------------------
    %    The third column selects the detection SOURCE:
    %       'names'      -> match patterns against installed products/add-ons
    %                       and configured MEX compilers.
    %       'registry'   -> scan the Windows "Uninstall" registry keys for a
    %                       DisplayName matching the patterns (used for
    %                       standalone apps such as NXP FreeMASTER).
    requirements = {
        % Display name                                     Match patterns (regexp, case-insensitive)              Source
        'MATLAB Coder',                                    {'^MATLAB Coder$'},                                     'names'
        'Simulink Coder',                                  {'^Simulink Coder$'},                                   'names'
        'Embedded Coder',                                  {'^Embedded Coder$'},                                   'names'
        'Stateflow',                                       {'^Stateflow$'},                                        'names'
        'Simscape',                                        {'^Simscape$'},                                         'names'
        'Simscape Electrical',                             {'^Simscape Electrical$'},                              'names'
        'AUTOSAR Blockset',                                {'^AUTOSAR Blockset$'},                                 'names'
        'MinGW-w64 C/C++ Compiler',                        {'MinGW'},                                              'names'
        'MBDT for S32K3',                                  {'S32K3.*Model-?Based Design', 'Model-?Based Design.*S32K3', 'S32K3'}, 'names'
        'Embedded Coder Support Package for ARM Cortex-M', {'Cortex-?M'},                                          'names'
        'NXP FreeMASTER',                                  {'FreeMASTER'},                                         'registry'
    };

    reqNames    = requirements(:, 1);
    reqPatterns = requirements(:, 2);
    reqSource   = requirements(:, 3);
    nReq        = numel(reqNames);

    % ---------------------------------------------------------------------
    % 2. Gather the list of installed product names (from VER) and installed
    %    add-on / support package names (from installedAddons).
    % ---------------------------------------------------------------------
    installedNames = getInstalledProductNames();
    installedNames = [installedNames; getInstalledAddonNames()];
    installedNames = [installedNames; getMexCompilerNames()];

    % Clean up: drop empties and duplicates.
    installedNames = installedNames(~cellfun(@isempty, installedNames));
    installedNames = unique(installedNames, 'stable');

    % ---------------------------------------------------------------------
    % 3. Evaluate every requirement against the installed names.
    % ---------------------------------------------------------------------
    status  = false(nReq, 1);
    matched = cell(nReq, 1);

    for k = 1:nReq
        patterns = reqPatterns{k};
        switch lower(reqSource{k})
            case 'registry'
                [ok, hit] = matchRegistryUninstall(patterns);
            otherwise   % 'names'
                [ok, hit] = matchAny(installedNames, patterns);
        end
        status(k)  = ok;
        matched{k} = hit;   % the installed name that satisfied the requirement (or '')
    end

    % ---------------------------------------------------------------------
    % 4. Build the results table.
    % ---------------------------------------------------------------------
    Requirement = reqNames(:);
    Installed   = status(:);
    FoundAs     = matched(:);
    results = table(Requirement, Installed, FoundAs);

    % ---------------------------------------------------------------------
    % 5. Print a human-readable report.
    % ---------------------------------------------------------------------
    fprintf('\n=== MATLAB Installation Validation ===\n\n');
    for k = 1:nReq
        if status(k)
            fprintf('  [ PASS ]  %-48s  (found: %s)\n', reqNames{k}, matched{k});
        else
            fprintf('  [ FAIL ]  %-48s  (not found)\n', reqNames{k});
        end
    end

    nPass = sum(status);
    fprintf('\n  Summary: %d of %d requirements satisfied.\n\n', nPass, nReq);

    % ---------------------------------------------------------------------
    % 6. Raise an error if anything is missing (useful for CI/automation).
    % ---------------------------------------------------------------------
    if ~all(status)
        missing = strjoin(reqNames(~status), ', ');
        error('validateMatlabInstallation:MissingProducts', ...
              'The following required products/add-ons are missing: %s', missing);
    end
end

% =========================================================================
% Helper functions
% =========================================================================

function names = getInstalledProductNames()
%GETINSTALLEDPRODUCTNAMES Return the Name of every installed product (VER).
    names = {};
    try
        v = ver;
        if ~isempty(v)
            names = {v.Name}';
        end
    catch me
        warning('validateMatlabInstallation:VerFailed', ...
                'Could not query installed products via VER: %s', me.message);
    end
end

function names = getInstalledAddonNames()
%GETINSTALLEDADDONNAMES Return the Name of every installed add-on/support pkg.
    names = {};
    try
        addons = matlab.addons.installedAddons();
        if ~isempty(addons) && ismember('Name', addons.Properties.VariableNames)
            names = cellstr(string(addons.Name));
        end
    catch me
        % installedAddons may not exist on very old releases; not fatal.
        warning('validateMatlabInstallation:AddonsFailed', ...
                'Could not query installed add-ons: %s', me.message);
    end
end

function names = getMexCompilerNames()
%GETMEXCOMPILERNAMES Return the names of configured C/C++ MEX compilers.
%   This helps detect MinGW even when it is registered only as a compiler.
    names = {};
    try
        cfg = [mex.getCompilerConfigurations('C',   'Installed'), ...
               mex.getCompilerConfigurations('C++', 'Installed')];
        if ~isempty(cfg)
            names = unique({cfg.Name}', 'stable');
        end
    catch me
        warning('validateMatlabInstallation:MexFailed', ...
                'Could not query MEX compiler configurations: %s', me.message);
    end
end

function [ok, hit] = matchAny(names, patterns)
%MATCHANY True if any name matches any of the (regexp) patterns.
%   Returns the first matching installed name in HIT (or '' if none).
    ok  = false;
    hit = '';
    if ischar(patterns)
        patterns = {patterns};
    end
    for p = 1:numel(patterns)
        idx = ~cellfun(@isempty, regexpi(names, patterns{p}, 'once'));
        if any(idx)
            ok  = true;
            first = find(idx, 1, 'first');
            hit = names{first};
            return;
        end
    end
end

function [ok, hit] = matchRegistryUninstall(patterns)
%MATCHREGISTRYUNINSTALL Detect a standalone app via the Windows Uninstall keys.
%   Scans the "Uninstall" registry hives (native 64-bit, 32-bit WOW6432Node,
%   and per-user views) for an entry whose DisplayName matches any of the
%   (regexp) PATTERNS. Returns OK = true and HIT set to the matching
%   DisplayName when found.
%
%   Implementation note: MATLAB's WINQUERYREG cannot enumerate the SUBKEYS
%   of a registry key (its 'name' option returns value names, not subkey
%   names), so the Windows built-in REG QUERY command is used instead. It
%   recursively lists every Uninstall entry's DisplayName value, which we
%   then pattern-match.
%
%   On non-Windows platforms the registry is not available; OK is returned
%   as false with an explanatory HIT string so the caller can report it.
    ok  = false;
    hit = '';

    if ~ispc
        hit = 'N/A (registry check only supported on Windows)';
        return;
    end

    if ischar(patterns)
        patterns = {patterns};
    end

    % Registry roots/keys that hold per-machine and per-user uninstall data.
    hives = { ...
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; ...
        'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; ...
        'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'};

    for h = 1:numel(hives)
        % Recursively list every DisplayName value under this Uninstall hive.
        cmd = sprintf('reg query "%s" /s /v DisplayName', hives{h});
        [st, out] = system(cmd);
        if st ~= 0 || isempty(out)
            continue;   % hive absent or no DisplayName values present.
        end

        % Each match appears as: "    DisplayName    REG_SZ    <name>".
        lines = regexp(out, '\r?\n', 'split');
        for i = 1:numel(lines)
            tok = regexp(lines{i}, 'DisplayName\s+REG_\w+\s+(.*)$', ...
                         'tokens', 'once');
            if isempty(tok)
                continue;
            end
            displayName = strtrim(tok{1});

            for p = 1:numel(patterns)
                if ~isempty(regexpi(displayName, patterns{p}, 'once'))
                    ok  = true;
                    hit = displayName;
                    return;
                end
            end
        end
    end
end
