function name = print2eps(fig, padding, renderer)
%PRINT2EPS  Prints figures to eps with improved line styles
%
% Examples:
%   name = print2eps(fig_handle)
%   name = print2eps(fig_handle, export_options)
%   name = print2eps(fig_handle, export_options, print_options)
%
% This function saves a figure as an eps file, with two improvements over
% MATLAB's print command. First, it improves the line style, making dashed
% lines more like those on screen and giving grid lines a dotted line style.
% Secondly, it substitutes original font names back into the eps file,
% where these have been changed by MATLAB, for up to 11 different fonts.
%
% IN:
%   filename - string containing the name (optionally including full or
%              relative path) of the file the figure is to be saved as. A
%              ".eps" extension is added if not there already. If a path is
%              not specified, the figure is saved in the current directory.
%   fig_handle - The handle of the figure to be saved. Default: gcf().
%   export_options - array or struct of optional scalar values:
%       padding    - Scalar value of amount of padding to add to border around
%                    the cropped image, in points (if >1) or percent (if <1).
%                    Can be negative as well as positive; Default: 0
%       crop       - Crop amount. Deafult: 0
%       fontswap   - Whether to swap non-default fonts in figure. Default: true
%       renderer   - Renderer used to generate bounding-box. Default: 'opengl'
%   print_options - Additional parameter strings to be passed to the print command

% Copyright (C) Oliver Woodford 2008-2014, Yair Altman 2015-

    name = [tempname '.eps'];
    options = {'-loose'};
    options = [options renderer];

    if padding, bb_crop = true;  fontswap = true;
    else        bb_crop = false; fontswap = false;
    end

    % Set paper size
    old_pos_mode = get(fig, 'PaperPositionMode');
    old_orientation = get(fig, 'PaperOrientation');
    set(fig, 'PaperPositionMode', 'auto', 'PaperOrientation', 'portrait');

    % Find all the used fonts in the figure
    font_handles = findall(fig, '-property', 'FontName');
    fonts = get(font_handles, 'FontName');
    if isempty(fonts)
        fonts = {};
    elseif ~iscell(fonts)
        fonts = {fonts};
    end

    % Map supported font aliases onto the correct name
    fontsl = lower(fonts);
    for a = 1:numel(fonts)
        f = fontsl{a};
        f(f==' ') = [];
        switch f
            case {'times', 'timesnewroman', 'times-roman'}
                fontsl{a} = 'times-roman';
            case {'arial', 'helvetica'}
                fontsl{a} = 'helvetica';
            case {'newcenturyschoolbook', 'newcenturyschlbk'}
                fontsl{a} = 'newcenturyschlbk';
            otherwise
        end
    end
    fontslu = unique(fontsl);

    % Determine the font swap table
    if fontswap
        matlab_fonts = {'Helvetica', 'Times-Roman', 'Palatino', 'Bookman', 'Helvetica-Narrow', 'Symbol', ...
                        'AvantGarde', 'NewCenturySchlbk', 'Courier', 'ZapfChancery', 'ZapfDingbats'};
        matlab_fontsl = lower(matlab_fonts);
        require_swap = find(~ismember(fontslu, matlab_fontsl));
        unused_fonts = find(~ismember(matlab_fontsl, fontslu));
        font_swap = cell(3, min(numel(require_swap), numel(unused_fonts)));
        fonts_new = fonts;
        for a = 1:size(font_swap, 2)
            font_swap{1,a} = find(strcmp(fontslu{require_swap(a)}, fontsl));
            font_swap{2,a} = matlab_fonts{unused_fonts(a)};
            font_swap{3,a} = fonts{font_swap{1,a}(1)};
            fonts_new(font_swap{1,a}) = font_swap(2,a);
        end
    else
        font_swap = [];
    end

    % Swap the fonts
    if ~isempty(font_swap)
        fonts_size = get(font_handles, 'FontSize');
        if iscell(fonts_size)
            fonts_size = cell2mat(fonts_size);
        end
        M = false(size(font_handles));

        % Loop because some changes may not stick first time, due to listeners
        c = 0;
        update = zeros(1000, 1);
        for b = 1:10 % Limit number of loops to avoid infinite loop case
            for a = 1:numel(M)
                M(a) = ~isequal(get(font_handles(a), 'FontName'), fonts_new{a}) || ~isequal(get(font_handles(a), 'FontSize'), fonts_size(a));
                if M(a)
                    set(font_handles(a), 'FontName', fonts_new{a}, 'FontSize', fonts_size(a));
                    c = c + 1;
                    update(c) = a;
                end
            end
            if ~any(M)
                break;
            end
        end

        % Compute the order to revert fonts later, without the need of a loop
        [update, M] = unique(update(1:c));
        [M, M] = sort(M);
        update = reshape(update(M), 1, []);
    end

    % MATLAB bug fix - black and white text can come out inverted sometimes
    % Find the white and black text
    black_text_handles = findall(fig, 'Type', 'text', 'Color', [0 0 0]);
    white_text_handles = findall(fig, 'Type', 'text', 'Color', [1 1 1]);
    % Set the font colors slightly off their correct values
    set(black_text_handles, 'Color', [0 0 0] + eps);
    set(white_text_handles, 'Color', [1 1 1] - eps);

    % MATLAB bug fix - white lines can come out funny sometimes
    % Find the white lines
    white_line_handles = findall(fig, 'Type', 'line', 'Color', [1 1 1]);
    % Set the line color slightly off white
    set(white_line_handles, 'Color', [1 1 1] - 0.00001);

    % Workaround for issue #45: lines in image subplots are exported in invalid color
    % In this case the -depsc driver solves the problem, but then all the other workarounds
    % below (for all the other issues) will fail, so it's better to let the user decide by
    % just issuing a warning and accepting the '-depsc' input parameter
    epsLevel2 = ~any(strcmpi(options,'-depsc'));
    if epsLevel2
        % Use -depsc2 (EPS color level-2) if -depsc (EPS color level-3) was not specifically requested
        options{end+1} = '-depsc2';
        % Issue a warning if multiple images & lines were found in the figure, and HG1 with painters renderer is used
        isPainters = any(strcmpi(options,'-painters'));
        if isPainters && ~using_hg2 && numel(findall(fig,'Type','image'))>1 && ~isempty(findall(fig,'Type','line'))
            warning('YMA:export_fig:issue45', ...
                    ['Multiple images & lines detected. In such cases, the lines might \n' ...
                     'appear with an invalid color due to an internal MATLAB bug (fixed in R2014b). \n' ...
                     'Possible workaround: add a ''-depsc'' or ''-opengl'' parameter to the export_fig command.']);
        end
    end

    % Fix issue #83: use numeric handles in HG1
    if ~using_hg2(fig),  fig = double(fig);  end
    
    % Workaround for when transparency is lost through conversion fig>EPS>PDF (issue #108)
    % Replace transparent patch RGB values with an ID value (rare chance that ID color is being used already)
    if using_hg2
        origAlphaColors = eps_maintainAlpha(fig);
    end

    % Print to eps file
    print(fig, options{:}, name);

    % Do post-processing on the eps file
    try
        % Read the EPS file into memory
        fstrm = read_write_entire_textfile(name);
    catch
        fstrm = '';
    end
    
    % Restore colors for transparent patches and apply the
    % setopacityalpha setting in the EPS file (issue #108)
    if using_hg2
        [~,fstrm] = eps_maintainAlpha(fig, fstrm, origAlphaColors);
    end
    
    % Fix for Matlab R2014b bug (issue #31): LineWidths<0.75 are not set in the EPS (default line width is used)
    try
        if ~isempty(fstrm) && using_hg2(fig)
            % Convert miter joins to line joins
            %fstrm = regexprep(fstrm, '\n10.0 ML\n', '\n1 LJ\n');
            % This is faster (the original regexprep could take many seconds when the axes contains many lines):
            fstrm = strrep(fstrm, sprintf('\n10.0 ML\n'), sprintf('\n1 LJ\n'));

            % In HG2, grid lines and axes Ruler Axles have a default LineWidth of 0.5 => replace en-bulk (assume that 1.0 LineWidth = 1.333 LW)
            %   hAxes=gca; hAxes.YGridHandle.LineWidth, hAxes.YRuler.Axle.LineWidth
            %fstrm = regexprep(fstrm, '(GC\n2 setlinecap\n1 LJ)\nN', '$1\n0.667 LW\nN');
            % This is faster:
            fstrm = strrep(fstrm, sprintf('GC\n2 setlinecap\n1 LJ\nN'), sprintf('GC\n2 setlinecap\n1 LJ\n0.667 LW\nN'));

            % This is more accurate but *MUCH* slower (issue #52)
            %{
            % Modify all thin lines in the figure to have 10x LineWidths
            hLines = findall(fig,'Type','line');
            hThinLines = [];
            for lineIdx = 1 : numel(hLines)
                thisLine = hLines(lineIdx);
                if thisLine.LineWidth < 0.75 && strcmpi(thisLine.Visible,'on')
                    hThinLines(end+1) = thisLine; %#ok<AGROW>
                    thisLine.LineWidth = thisLine.LineWidth * 10;
                end
            end

            % If any thin lines were found
            if ~isempty(hThinLines)
                % Prepare an EPS with large-enough line widths
                print(fig, options{:}, name);
                % Restore the original LineWidths in the figure
                for lineIdx = 1 : numel(hThinLines)
                    thisLine = handle(hThinLines(lineIdx));
                    thisLine.LineWidth = thisLine.LineWidth / 10;
                end

                % Compare the original and the new EPS files and correct the original stream's LineWidths
                fstrm_new = read_write_entire_textfile(name);
                idx = 500;  % skip heading with its possibly-different timestamp
                markerStr = sprintf('10.0 ML\nN');
                markerLen = length(markerStr);
                while ~isempty(idx) && idx < length(fstrm)
                    lastIdx = min(length(fstrm), length(fstrm_new));
                    delta = fstrm(idx+1:lastIdx) - fstrm_new(idx+1:lastIdx);
                    idx = idx + find(delta,1);
                    if ~isempty(idx) && ...
                            isequal(fstrm(idx-markerLen+1:idx), markerStr) && ...
                            ~isempty(regexp(fstrm_new(idx-markerLen+1:idx+12),'10.0 ML\n[\d\.]+ LW\nN')) %#ok<RGXP1>
                        value = str2double(regexprep(fstrm_new(idx:idx+12),' .*',''));
                        if isnan(value), break; end  % something's wrong... - bail out
                        newStr = sprintf('%0.3f LW\n',value/10);
                        fstrm = [fstrm(1:idx-1) newStr fstrm(idx:end)];
                        idx = idx + 12;
                    else
                        break;
                    end
                end
            end
            %}

            % This is much faster although less accurate: fix all non-gray lines to have a LineWidth of 0.75 (=1 LW)
            % Note: This will give incorrect LineWidth of 075 for lines having LineWidth<0.75, as well as for non-gray grid-lines (if present)
            %       However, in practice these edge-cases are very rare indeed, and the difference in LineWidth should not be noticeable
            %fstrm = regexprep(fstrm, '([CR]C\n2 setlinecap\n1 LJ)\nN', '$1\n1 LW\nN');
            % This is faster (the original regexprep could take many seconds when the axes contains many lines):
            fstrm = strrep(fstrm, sprintf('\n2 setlinecap\n1 LJ\nN'), sprintf('\n2 setlinecap\n1 LJ\n1 LW\nN'));
        end
    catch err
        fprintf(2, 'Error fixing LineWidths in EPS file: %s\n at %s:%d\n', err.message, err.stack(1).file, err.stack(1).line);
    end

    % Reset the font and line colors
    set(black_text_handles, 'Color', [0 0 0]);
    set(white_text_handles, 'Color', [1 1 1]);
    set(white_line_handles, 'Color', [1 1 1]);

    % Reset paper size
    set(fig, 'PaperPositionMode', old_pos_mode, 'PaperOrientation', old_orientation);

    % Reset the font names in the figure
    if ~isempty(font_swap)
        for a = update
            set(font_handles(a), 'FontName', fonts{a}, 'FontSize', fonts_size(a));
        end
    end

    % Bail out if EPS post-processing is not possible
    if isempty(fstrm)
        warning('Loading EPS file failed, so unable to perform post-processing. This is usually because the figure contains a large number of patch objects. Consider exporting to a bitmap format in this case.');
        return
    end

    % Replace the font names
    if ~isempty(font_swap)
        for a = 1:size(font_swap, 2)
            %fstrm = regexprep(fstrm, [font_swap{1,a} '-?[a-zA-Z]*\>'], font_swap{3,a}(~isspace(font_swap{3,a})));
            fstrm = regexprep(fstrm, font_swap{2,a}, font_swap{3,a}(~isspace(font_swap{3,a})));
        end
    end

    % Move the bounding box to the top of the file (HG2 only), or fix the line styles (HG1 only)
    if using_hg2(fig)
        % Move the bounding box to the top of the file (HG2 only)
        [s, e] = regexp(fstrm, '%%BoundingBox: [^%]*%%');
        if numel(s) == 2
            fstrm = fstrm([1:s(1)-1 s(2):e(2)-2 e(1)-1:s(2)-1 e(2)-1:end]);
        end
    else
        % Fix the line styles (HG1 only)
        fstrm = fix_lines(fstrm);
    end

    % Apply the bounding box padding & cropping, replacing Matlab's print()'s bounding box
    if bb_crop
        % Calculate a new bounding box based on a bitmap print
        % 1. Determine the Matlab BoundingBox and PageBoundingBox
        [s,e] = regexp(fstrm, '%%BoundingBox: [^%]*%%'); % location BB in eps file
        if numel(s)==2, s=s(2); e=e(2); end
        aa = fstrm(s+15:e-3); % dimensions bb - STEP1
        bb_matlab = cell2mat(textscan(aa,'%f32%f32%f32%f32'));  % dimensions bb - STEP2

        [s,e] = regexp(fstrm, '%%PageBoundingBox: [^%]*%%'); % location bb in eps file
        if numel(s)==2, s=s(2); e=e(2); end
        aa = fstrm(s+19:e-3); % dimensions bb - STEP1
        pagebb_matlab = cell2mat(textscan(aa,'%f32%f32%f32%f32'));  % dimensions bb - STEP2

        % 2. Create a bitmap image and use cropfig to create the relative
        %    bb with respect to the PageBoundingBox
        [A, bcol] = print2array(fig, 1, renderer);
        [aa, aa, aa, bb_rel] = cropfig(A, [], padding);

        % 3. Calculate the new Bounding Box
        pagew = pagebb_matlab(3)-pagebb_matlab(1);
        pageh = pagebb_matlab(4)-pagebb_matlab(2);
        %bb_new = [pagebb_matlab(1)+pagew*bb_rel(1) pagebb_matlab(2)+pageh*bb_rel(2) ...
        %          pagebb_matlab(1)+pagew*bb_rel(3) pagebb_matlab(2)+pageh*bb_rel(4)];
        bb_new = pagebb_matlab([1,2,1,2]) + [pagew,pageh,pagew,pageh].*bb_rel;  % clearer
        bb_offset = (bb_new-bb_matlab) + [-1,-1,1,1];  % 1px margin so that cropping is not TOO tight

        % Apply the bounding box padding
        if padding
            if abs(padding)<1
                padding = round((mean([bb_new(3)-bb_new(1) bb_new(4)-bb_new(2)])*padding)/0.5)*0.5; % ADJUST BB_PADDING
            end
            add_padding = @(n1, n2, n3, n4) sprintf(' %d', str2double({n1, n2, n3, n4}) + [-padding -padding padding padding] + bb_offset);
        else
            add_padding = @(n1, n2, n3, n4) sprintf(' %d', str2double({n1, n2, n3, n4}) + bb_offset); % fix small but noticeable bounding box shift
        end
        fstrm = regexprep(fstrm, '%%BoundingBox:[ ]+([-]?\d+)[ ]+([-]?\d+)[ ]+([-]?\d+)[ ]+([-]?\d+)', '%%BoundingBox:${add_padding($1, $2, $3, $4)}');
    end

    % Fix issue #44: white artifact lines appearing in patch exports
    % Note: the problem is due to the fact that Matlab's print() function exports patches
    %       as a combination of filled triangles, and a white line appears where the triangles touch
    % In the workaround below, we will modify such dual-triangles into a filled rectangle.
    % We are careful to only modify regexps that exactly match specific patterns - it's better to not
    % correct some white-line artifacts than to change the geometry of a patch, or to corrupt the EPS.
    %   e.g.: '0 -450 937 0 0 450 3 MP PP 937 0 0 -450 0 450 3 MP PP' => '0 -450 937 0 0 450 0 0 4 MP'
    fstrm = regexprep(fstrm, '\n([-\d.]+ [-\d.]+) ([-\d.]+ [-\d.]+) ([-\d.]+ [-\d.]+) 3 MP\nPP\n\2 \1 \3 3 MP\nPP\n','\n$1 $2 $3 0 0 4 MP\nPP\n');
    fstrm = regexprep(fstrm, '\n([-\d.]+ [-\d.]+) ([-\d.]+ [-\d.]+) ([-\d.]+ [-\d.]+) 3 MP\nPP\n\2 \3 \1 3 MP\nPP\n','\n$1 $2 $3 0 0 4 MP\nPP\n');
    fstrm = regexprep(fstrm, '\n([-\d.]+ [-\d.]+) ([-\d.]+ [-\d.]+) ([-\d.]+ [-\d.]+) 3 MP\nPP\n\3 \1 \2 3 MP\nPP\n','\n$1 $2 $3 0 0 4 MP\nPP\n');
    fstrm = regexprep(fstrm, '\n([-\d.]+ [-\d.]+) ([-\d.]+ [-\d.]+) ([-\d.]+ [-\d.]+) 3 MP\nPP\n\3 \2 \1 3 MP\nPP\n','\n$1 $2 $3 0 0 4 MP\nPP\n');

    % Write out the fixed eps file
    read_write_entire_textfile(name, fstrm);
end

function [StoredColors, fstrm] = eps_maintainAlpha(fig_, fstrm, StoredColors)
    if nargin == 1
        ars = findobj(fig_,'Type','Area');
        StoredColors={};
        for ar = 1:length(ars)
            if strcmp(ars(ar).Face.ColorType, 'truecoloralpha')
                StoredColors{end+1}=ars(ar).Face.ColorData;
                ars(ar).Face.ColorData = uint8([101; 102; length(StoredColors); 255]);
            end
        end
    else
        %Find the transparent patches
        ars = findobj(fig_,'Type','Area');
        ar_stored = 0;
        try
            for ar = 1:length(ars)
                if strcmp(ars(ar).Face.ColorType, 'truecoloralpha')
                    ar_stored = ar_stored + 1;
                    stored = StoredColors{ar_stored}';
                    %Restore the EPS files patch color
                    colorID = num2str(round([101 102 ar_stored]/255,3),'%.3g %.3g %.3g'); %ID for searching
                    originalColor = num2str(round(double(stored(1:end-1))/255,3),'%.3g %.3g %.3g'); %Replace with original color
                    alpha_ = num2str(round(double(stored(end))/255,3),'%.3g'); %Convert alpha value for EPS
                    %Find and replace
                    fstrm = strrep(fstrm, ...
                        sprintf(['CT\n' colorID ' RC\nN\n']), ...
                        sprintf(['CT\n' originalColor ' RC\n' alpha_ ' .setopacityalpha true\nN\n']));

                    %Restore the figures patch color
                    ars(ar).Face.ColorData = StoredColors{ar_stored};
                end
            end
        catch err
            fprintf(2, 'Error maintaining transparency in EPS file: %s\n at %s:%d\n', err.message, err.stack(1).file, err.stack(1).line);
        end
    end
end

function fstrm = read_write_entire_textfile(fname, fstrm)
    modes = {'rt', 'wt'};
    writing = nargin > 1;
    fh = fopen(fname, modes{1+writing});
    if fh == -1
        error('Unable to open file %s.', fname);
    end
    try
        if writing
            fwrite(fh, fstrm, 'char*1');
        else
            fstrm = fread(fh, '*char')';
        end
    catch ex
        fclose(fh);
        rethrow(ex);
    end
    fclose(fh);
end

function fstrm = fix_lines(fstrm, fname2)
%FIX_LINES  Improves the line style of eps files generated by print
%
% Examples:
%   fix_lines fname
%   fix_lines fname fname2
%   fstrm_out = fixlines(fstrm_in)
%
% This function improves the style of lines in eps files generated by
% MATLAB's print function, making them more similar to those seen on
% screen. Grid lines are also changed from a dashed style to a dotted
% style, for greater differentiation from dashed lines.
%
%   fname - Name or path of source eps file.
%   fname2 - Name or path of destination eps file. Default: same as fname.
%   fstrm_in - File contents of a MATLAB-generated eps file.
%   fstrm_out - Contents of the eps file with line styles fixed.
%
% Copyright: (C) Oliver Woodford, 2008-2014

if using_hg2
    warning('export_fig:hg2','The fix_lines function should not be used in this Matlab version.');
end
    
if nargout == 0 || nargin > 1
    if nargin < 2
        % Overwrite the input file
        fname2 = fstrm;
    end
    % Read in the file
    fstrm = read_write_entire_textfile(fstrm);
end

% Move any embedded fonts after the postscript header
if strcmp(fstrm(1:15), '%!PS-AdobeFont-')
    % Find the start and end of the header
    ind = regexp(fstrm, '[\n\r]%!PS-Adobe-');
    [ind2, ind2] = regexp(fstrm, '[\n\r]%%EndComments[\n\r]+');
    % Put the header first
    if ~isempty(ind) && ~isempty(ind2) && ind(1) < ind2(1)
        fstrm = fstrm([ind(1)+1:ind2(1) 1:ind(1) ind2(1)+1:end]);
    end
end

% Make sure all line width commands come before the line style definitions,
% so that dash lengths can be based on the correct widths
% Find all line style sections
ind = [regexp(fstrm, '[\n\r]SO[\n\r]'),... % This needs to be here even though it doesn't have dots/dashes!
       regexp(fstrm, '[\n\r]DO[\n\r]'),...
       regexp(fstrm, '[\n\r]DA[\n\r]'),...
       regexp(fstrm, '[\n\r]DD[\n\r]')];
ind = sort(ind);
% Find line width commands
[ind2, ind3] = regexp(fstrm, '[\n\r]\d* w[\n\r]');
% Go through each line style section and swap with any line width commands
% near by
b = 1;
m = numel(ind);
n = numel(ind2);
for a = 1:m
    % Go forwards width commands until we pass the current line style
    while b <= n && ind2(b) < ind(a)
        b = b + 1;
    end
    if b > n
        % No more width commands
        break;
    end
    % Check we haven't gone past another line style (including SO!)
    if a < m && ind2(b) > ind(a+1)
        continue;
    end
    % Are the commands close enough to be confident we can swap them?
    if (ind2(b) - ind(a)) > 8
        continue;
    end
    % Move the line style command below the line width command
    fstrm(ind(a)+1:ind3(b)) = [fstrm(ind(a)+4:ind3(b)) fstrm(ind(a)+1:ind(a)+3)];
    b = b + 1;
end

% Find any grid line definitions and change to GR format
% Find the DO sections again as they may have moved
ind = int32(regexp(fstrm, '[\n\r]DO[\n\r]'));
if ~isempty(ind)
    % Find all occurrences of what are believed to be axes and grid lines
    ind2 = int32(regexp(fstrm, '[\n\r] *\d* *\d* *mt *\d* *\d* *L[\n\r]'));
    if ~isempty(ind2)
        % Now see which DO sections come just before axes and grid lines
        ind2 = repmat(ind2', [1 numel(ind)]) - repmat(ind, [numel(ind2) 1]);
        ind2 = any(ind2 > 0 & ind2 < 12); % 12 chars seems about right
        ind = ind(ind2);
        % Change any regions we believe to be grid lines to GR
        fstrm(ind+1) = 'G';
        fstrm(ind+2) = 'R';
    end
end

% Define the new styles, including the new GR format
% Dot and dash lengths have two parts: a constant amount plus a line width
% variable amount. The constant amount comes after dpi2point, and the
% variable amount comes after currentlinewidth. If you want to change
% dot/dash lengths for a one particular line style only, edit the numbers
% in the /DO (dotted lines), /DA (dashed lines), /DD (dot dash lines) and
% /GR (grid lines) lines for the style you want to change.
new_style = {'/dom { dpi2point 1 currentlinewidth 0.08 mul add mul mul } bdef',... % Dot length macro based on line width
             '/dam { dpi2point 2 currentlinewidth 0.04 mul add mul mul } bdef',... % Dash length macro based on line width
             '/SO { [] 0 setdash 0 setlinecap } bdef',... % Solid lines
             '/DO { [1 dom 1.2 dom] 0 setdash 0 setlinecap } bdef',... % Dotted lines
             '/DA { [4 dam 1.5 dam] 0 setdash 0 setlinecap } bdef',... % Dashed lines
             '/DD { [1 dom 1.2 dom 4 dam 1.2 dom] 0 setdash 0 setlinecap } bdef',... % Dot dash lines
             '/GR { [0 dpi2point mul 4 dpi2point mul] 0 setdash 1 setlinecap } bdef'}; % Grid lines - dot spacing remains constant

% Construct the output
% This is the original (memory-intensive) code:
%first_sec = strfind(fstrm, '% line types:'); % Isolate line style definition section
%[second_sec, remaining] = strtok(fstrm(first_sec+1:end), '/');
%[remaining, remaining] = strtok(remaining, '%');
%fstrm = [fstrm(1:first_sec) second_sec sprintf('%s\r', new_style{:}) remaining];
fstrm = regexprep(fstrm,'(% line types:.+?)/.+?%',['$1',sprintf('%s\r',new_style{:}),'%']);

% Write the output file
if nargout == 0 || nargin > 1
    read_write_entire_textfile(fname2, fstrm);
end
end
