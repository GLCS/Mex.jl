classdef jl
    %JL static class encapsulating MATLAB-side functionality for mexjulia
    % Call julia methods with jl.call and jl.call_kw, or call specially-designed
    % 'MEX-like' Julia methods with jl.mex.
    
    methods (Static)

        % Call a MEX-like Julia function. Note that for this call to work,
        % Julia must have already been initialized, either with jl.call(), or
        % manually with jl.init()
        %
        % fn - the name of the function to call
        %
        % A MEX-like function is one that can be invoked with a value of type
        % `Vector{MxArray}` and returns a collection of values for which a
        % conversion to `MxArray` exists.
        function varargout = mex(fn, varargin)
            % take at least one return value from mexjulia
            nout = max(1, nargout);
            % check initialization
            jl.check_init();
            % call julia function
            [err, varargout{1:nout}] = mexjulia('jl_mex', fn, varargin{:});
            % throw error if julia code failed
            if ~islogical(err); throw(err); end
        end
        
        % Interpret string(s) as Julia expression(s), returning value(s).
        function varargout = eval(expr)
            [varargout{1:nargout}] = jl.mex('Mex.jl_eval', expr);
        end

        % Call a Julia function, possibly with keyword arguments, returning its
        % value.
        %
        % fn - the name of the function to call
        % npos - the number of arguments to be treated as positional
        %
        % Arguments beyond the first npos are assumed to come in key/value
        % pairs.
        %
        % If npos < 0 all arguments are assumed to be positional.
        function varargout = callkw(fn, npos, varargin)
            if npos >= 0
                nkw = length(varargin) - npos;
                if nkw < 0
                    error('The number of positional arguments exceeds the total number of arguments.');
                elseif mod(nkw,2) ~= 0
                    error('The number of keyword arguments is %u, but must be even.', nkw);
                end
            end
            [varargout{1:nargout}] = jl.mex('Mex.jl_call_kw', fn, int32(npos), varargin{:});
        end
        
        % Call a Julia function with the given (positional) arguments, returning its value.
        %
        % fn - the name of the function to call
        function varargout = call(fn, varargin)
            [varargout{1:nargout}] = jl.callkw(fn, -1, varargin{:});
        end
        
        % Wrap a Julia function in a MATLAB function handle.
        %
        % fn - the name of the function to wrap
        % npos - if provided, the number of arguments to be treated as
        % positional
        function hdl = wrap(fn, npos)
            if nargin < 2; npos = -1; end
            hdl = @(varargin) jl.callkw(fn, npos, varargin{:});
        end
        
        % Wrap a MEX-like Julia function in a MATLAB function handle.
        %
        % fn - the name of the function to wrap
        function hdl = wrapmex(fn)
            % check if julia is initialized
            jl.check_init();
            hdl = @(varargin) jl.mex(fn, varargin{:});
        end
        
        % Include a file in the Julia runtime
        function include(fl)
            % check if julia is initialized
            jl.check_init();
            mexjulia(true, sprintf('Base.include(Main,"%s");',jl.forward_slashify(fl)));
        end
        
        % Simple Julia REPL mode
        function repl(prompt, doneq)
            if nargin < 2
                doneq = @(expr)startsWith(expr,';');
                if nargin < 1
                    prompt = 'julia> ';
                end
            end
            
            while true
                expr = input(prompt, 's');
                if doneq(expr), break, end
                if endsWith(expr,';')
                    jl.eval(expr);
                else
                    jl.eval(expr)
                end
            end
        end
        
        % Check that the Julia runtime is initialized (initialize if necessary).
        function check_init()
            persistent isInit; if isempty(isInit); isInit = false; end
            if ~isInit
                jl.init()
                % ensure initialization worked
                isInit = mexjulia();
            end
        end
        
        function init()
            % check that the mexfunction exists
            if exist('mexjulia','file') ~= 3
                error('It appears the mexjulia MEX function is missing. Try re-building "Mex.jl"');
            end
            
            % load runtime settings from matfile
            jldict = load('jldict', 'julia_home', 'sys_image', 'lib_path');
            
            if ispc % cd to Julia dir so that the mexfunction can find DLLs
                old_dir = pwd;
                cd(jldict.julia_home);
            end
            
            % make sure MATLAB_HOME points to _this_ version of MATLAB.
            setenv('MATLAB_HOME', jl.matlab_dir);

            % basic runtime initialization
            mexjulia(false, jldict.julia_home, jldict.sys_image, jldict.lib_path);
            
            % load startup file
            mexjulia(true, sprintf('%s\n', ...
            'let startupfile = !isempty(DEPOT_PATH) ? abspath(DEPOT_PATH[1], "config", "startup_mexjulia.jl") : "" ',...
            '    isfile(startupfile) && Base.JLOptions().startupfile != 2 && Base.include(Main, startupfile) ',...
            'end '));

            % add MATLAB.jl
            if getenv('CI')
                mexjulia(true, 'using Pkg; Pkg.add("MATLAB");')
            end

            % load required packages
            mexjulia(true, 'using MATLAB, Mex');

            % restore the path
            if ispc
                cd(old_dir);
            end
        end
        
        % path to the root of this version of MATLAB
        function mh = matlab_dir()
            mh = fileparts(fileparts(fileparts(fileparts(which('path')))));
        end
        
        % replace backslashes with forward slashes on pcs (id fn otherwise)
        function p = forward_slashify(p)
            if ispc
                p = regexp(p, filesep, 'split');
                p = [sprintf('%s/', p{1:end-1}) p{end}];
            end
        end
        
    end
    
end
