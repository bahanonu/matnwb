function fvstr = fillValidators(propnames, props, namespacereg)
fvstr = '';
for i=1:length(propnames)
    nm = propnames{i};
    prop = props.properties(nm);
    if startsWith(class(prop), 'file.')
        fvstr = [fvstr ...
            'function validate_' nm '(obj, val)' newline...
            fillUnitValidation(nm, prop, namespacereg) newline...
            'end' newline];
    else %primitive type
        fvstr = [fvstr...
            'function validate_' nm '(obj, val)' newline...
            fillDtypeValidation(nm, prop, {1}, namespacereg) newline...
            'end' newline];
    end
end
end

function fuvstr = fillUnitValidation(name, prop, namespacereg)
fuvstr = '';
if isa(prop, 'file.Dataset')
    if prop.linkable
        fuvstr = [...
            'if isa(val, ''types.untyped.Link'')' newline...
            '    return;' newline... %TODO
            'end' newline];
    end
    if prop.isClass
        namespace = namespacereg.getNamespace(prop.type).name;
        fullclassname = ['types.' namespace '.' prop.type];
        fuvstr = fillClassValidation(fullclassname, prop.isConstrainedSet);
    else
        fuvstr = [fuvstr...
            fillDtypeValidation(name, prop.dtype, prop.shape, namespacereg)...
            fillDimensionValidation(prop.dtype, prop.shape)];
    end
elseif isa(prop, 'file.Group')
    namespace = namespacereg.getNamespace(prop.type).name;
    fulltypename = ['types.' namespace '.' prop.type];
    fuvstr = fillClassValidation(fulltypename, prop.isConstrainedSet);
elseif isa(prop, 'file.Attribute')
    fuvstr = [fuvstr fillDtypeValidation(name, prop.dtype, {1}, namespacereg)];
else %Link
    namespace = namespacereg.getNamespace(prop.type).name;
    errmsg = ['error(''Property ' prop.name ' must be a reference to a types.' ...
        namespace '.' prop.type ''');'];
    fuvstr = [...
        'if ~isa(val, ''' prop.type ''')' newline...
        '    ' errmsg newline...
        'end' newline];
end
end

function fdvstr = fillDimensionValidation(type, shape)
if strcmp(type, 'any') || (strcmp(type, 'char') && isempty(shape))
    fdvstr = '';
    return;
end
validshapetokens = cell(size(shape));
for i=1:length(shape)
    validshapetokens{i} = ['[' strtrim(evalc('disp(shape{i})')) ']'];
end
fdvstr = [...
    'valsz = size(val);' newline...
    'validshapes = {' strjoin(validshapetokens, ' ') '};' newline];

if strcmp(type, 'char')
    fdvstr = [fdvstr...
        'if ischar(val)' newline...
        '    for i=1:length(validshapes)' newline...
        '        vs = validshapes{i};' newline...
        '        if ndims(vs) == 2 && any(vs == 1)' newline...
        '            return;' newline...
        '        end' newline...
        '    end' newline...
        'end' newline];
else
    
end
fdvstr = [fdvstr 'end' newline];

switch type
    case {'double' 'int64' 'uint64'}
    case 'char'
        %cell
end
end

function fcvstr = fillClassValidation(fulltypename, constrained)
if constrained
    errmsg = ['error(''The class (or superclass) of this property must be '...
        fulltypename ' or a cell array consisting of this class/superclass.'');'];
    cellerrmsg = [...
        'error(''All classes (or superclasses) in this cell array must be a '...
        fulltypename ''');'];
    fcvstr = [...
        'if ~isa(val, ''' fulltypename ''') || ~iscell(val)' newline...
        '    ' errmsg newline...
        'end' newline...
        'if iscell(val)' newline...
        '    for i=1:length(val)' newline...
        '        if ~isa(val{i}, ''' fulltypename ''')' newline...
        '            ' cellerrmsg newline...
        '        end' newline...
        '    end' newline...
        'end' newline];
else
    errmsg = ['error(''This property must be of type ' fulltypename ''');'];
    fcvstr = [...
        'if ~isa(val, ''' fulltypename ''')' newline...
        '    ' errmsg newline...
        'end' newline];
end
end

function fdvstr = fillDtypeValidation(name, type, shape, namespacereg)
if ~ischar(type)
    if isstruct(type)
        %compound types are tables
        fnm = fieldnames(type);
        fnmstr = ['{' strtrim(evalc('disp(fnm)')) '}'];
        fdvstr = [...
            'if ~istable(val)' newline...
            '    error(''Property ' name ' must be a table.'');' newline...
            'end' newline...
            'allowedfnm = ' fnmstr ';' newline...
            'if ~isempty(intersect(allowedfnm, val.Properties.VariableNames))' newline...
            '   error(''Property ' name ' must be a table with variables ' fnmstr '.'');' newline...
            'end' newline];
        for i=1:length(fnm)
            nm = fnm{i};
            fdvstr = [fdvstr strrep(fillDtypeValidation(nm, type.(nm), {inf}, namespacereg), 'val', ['val.' nm])];
        end
    else
        %ref
        tt = type.get('target_type');
        ptt = namespacereg.getNamespace(tt).name;
        %handle object
        fdvstr = [...
            'if ~isa(val, ''' tt ''')' newline...
            '    error(''Property ' name ' must be a reference to a types.'...
            ptt '.' tt ''');' newline...
            'end' newline];
    end
    return;
end
errmsg = ['error(''Property ' name ' must be a ' type '.'');'];
typechck = '';
switch type
    case 'any'
    case 'double'
        typechck = '~isnumeric(val)';
    case {'int64' 'uint64'}
        typechck = '~isinteger(val)';
        if strcmp(type, 'uint64')
            typechck = [typechck ' || val < 0'];
        end
    case 'char'
        dimsz = numel(shape{1});
        if dimsz == 1
            %regular char array
            typechck = '~ischar(val)';
        else
            %multidim cell array
            typechck = '~iscellstr(val)';
        end
end
fdvstr = [...
    'if ' typechck newline...
    '    ' errmsg newline...
    'end' newline];

% special case for region reftype
if strcmp(name, 'region') && strcmp(type, 'double')
    fdvstr = [fdvstr...
        'targetobj = obj.target;' newline...
        'targetobj.table(val);' newline];
end
end