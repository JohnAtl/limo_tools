function [expected_chanlocs,channeighbstructmat,neighbours,savename] = limo_expected_chanlocs(varargin)

% This function loads an EEG dataset to create a file with the
% location of all expected channels and to create a neighbourhood
% distance matrix used to control for multiple comparisons.
%
% FORMAT: limo_expected_chanlocs
%         limo_expected_chanlocs(full path data set name)
%         limo_expected_chanlocs(data set name, path)
%         limo_expected_chanlocs(data set name, path,neighbour distance)
%
% INPUTS data set name is the name of a eeglab.set
%        path is the location of that file
%        neighbour distance is the distance between channels to buid the neighbourhood matrix
%        channeighbstructmat is the neighbourhood matrix
% 
% OUTPUTS expected_chanlocs structure that lists all the electrodes 
%         --> same as chanloc per subject
%         --> build across all subjects (should be like your cap before bad channel removal)
%         channeighbstructmat a matrix of electrode neighbourhood used in cluster analyses
%         neighbours the expected chanloc structure with the neighbours of each channel
%         savename, the default name generated to save data (not saved in nargout)
%
% See also LIMO_NEIGHBOURDIST LIMO_GET_CHANNEIGHBSTRUCMAT
% similar version from eeglab [STUDY neighbors] = std_prepare_neighbors( STUDY, ALLEEG, 'key', val)
% see also eeg_mergelocs 
%
% Guillaume Rousselet v1 11 June 2010
% Cyril Pernet v2 16 July 2010, we don't have to know which subject has the
% largest channel description  
% Cyril PErnet, 18 July 2012, get output channeighbstructmat so we can update
% subjects for tfce
% Marianne Latinus, May 2014 - create a cap with a minimum number
% of subjects per electrodes ; loop through all subjects
% ------------------------------
%  Copyright (C) LIMO Team 2019

%% variables set as defaults
min_subjects = 3; % we want at least 3 subjects per electrode for a set

global EEGLIMO
current_dir = pwd;

%% ask if data are from one subject or a set then get data
% ---------------------------------------------------------
if nargin == 0
    quest = questdlg('Make the Group level Channel location file from 1 subject or search throughout a set of subjects?','Selection','Set','One','Cancel','Set');
    if strcmp(quest,'Cancel')
        return
    else
        FileName = []; PathName = []; FilterIndex = [];
    end
elseif nargin == 1
    quest = 'One';  FilterIndex = 1;
    [PathName,f,e] = fileparts(varargin{1}); 
    FileName = [f e]; 
elseif nargin >= 2
    FileName = varargin{1}; 
    PathName = varargin{2}; 
    if size(FileName,1) == 1
        quest = 'One';
    else
        quest = 'Skip';
        Paths = cell(1,n); Files = cell(1,n); Names = cell(1,n);
        for n=1:size(FileName,1)
            [Paths{n},name,ext] = fileparts(FileName{n});
            Names{n} = [name ext];
            Files{n} = [Path{n} fielsep Names{n}];
        end
    end
    FilterIndex = 1;
else
    error('wrong number of arguments')
end

neighbourdist = [];
if nargin == 3
    neighbourdist = varargin{3};
end

if isempty(neighbourdist)
    neighbourdist = eval(cell2mat(inputdlg('enter neighbourhood distance','neighbourhood distance'))); % 0.37 for biosemi 128;
end


%% from 1 subject
% -----------------------
if strcmp(quest,'One')
    
    if isempty(FileName)
        [FileName,PathName,FilterIndex]=uigetfile('*.set','EEGLAB EEG dataset before electrode removal');
        if FilterIndex == 0
            return
        end
    end
    
    EEGLIMO=pop_loadset('filename', fullfile(PathName, FileName));
    expected_chanlocs = EEGLIMO.chanlocs;
    fprintf('Data set %s loaded \n',FileName);
    [neighbours,channeighbstructmat] = limo_get_channeighbstructmat(EEGLIMO,neighbourdist);
    for n=1:length(neighbours); N(n)=length(neighbours{n}.neighblabel); end
    if sum(channeighbstructmat(:)) == 0
       error('the neighbouring matrix is empty, it''s likely a distance issue, see imo_ft_neighbourselection.m');
    else
        cd (current_dir);
        savename = fullfile(PathName,[FileName(1:end-4) '_' num2str(round(mean(N))) '_neighbour_matrix']);
        if nargout == 0
            save(savename, 'neighbours', 'expected_chanlocs', 'channeighbstructmat') % save all in one file
            fprintf('expected_chanlocs & channeighbstructmatfile saved\n');
        end
    end
    
elseif strcmp(quest,'Set')   % from a set of subjects
    % -------------------------------------------
    
    %% get data
    [name,path,filt]=uigetfile({'LIMO.mat';'*.txt'; '*.mat'; '*.*'}, 'Pick a LIMO.mat (subject 1) or list', 'MultiSelect', 'on');
    if filt == 0
        return
    else
        [~,file,ext]=fileparts(name);
        if strcmp([file ext],'LIMO.mat') % we go for multiple LIMO.mat by hand
            Names{1} = name;
            Paths{1} = path;
            Files{1} = [path name];
            go = 1; 
            cd(current_dir); % go back to pwd...
        else
            go = 0;
            cd(path)
            if strcmp(name(end-3:end),'.txt')
                name = importdata(name);
            elseif strcmp(name(end-3:end),'.mat')
                name = load([path name]);
                name = getfield(name,cell2mat(fieldnames(name)));
            end
            
            for f=1:size(name,1)
                if ~exist(name{f},'file')
                    errordlg(sprintf('%s \n file not found',FileName{f}));
                    return
                else
                    Files{f} = name{f};
                    [Paths{f}, n,e] = fileparts(name{f});
                    Names{f} = [n e];
                end
            end
        end
    end
    
    index = 2;
    while go == 1
    [name,path] = uigetfile('LIMO.mat',['select LIMO file subject ',num2str(index)]);
        if name == 0
            go = 0;
        else
            if ~strcmp(name,'LIMO.mat')
                error(['you selected the file ' name ' but a LIMO.mat file is expected']);
            else
                Names{index} = name;
                Paths{index} = path;
                Files{index} = [path name];
                cd(current_dir)
                index = index + 1;
            end
        end
    end
    
    if index == 2
        expected_chanlocs   = [];
        channeighbstructmat = [];
        neighbours          = [];
        errordlg('you choose to create from a set and selected only one file?? ')
    end
    
    %% retreive all chanlocs and make up a cap where we have a least 3 subjects
    chanlocs      = cell(length(Paths),1);
    size_chanlocs = zeros(length(Paths),1);
    
    % retreive all chanlocs
    for i=1:length(Paths)
        load(Files{i})
        chanlocs{i}        = LIMO.data.chanlocs;
        size_chanlocs(i)   = size(LIMO.data.chanlocs,2);
        clear LIMO
        for c = 1:size_chanlocs(i)
            chan_labs{i,c} = chanlocs{i}(c).labels;
        end
    end
    
    % take the largest set as reference
    [nm,ref] = max(size_chanlocs);
    load(Files{ref})
    EEGLIMO.xmin     = LIMO.data.start;
    EEGLIMO.xmax     = LIMO.data.end;
    EEGLIMO.pnts     = length(LIMO.data.start:1000/LIMO.data.sampling_rate:LIMO.data.end); % note only for LIMO v2 in msec
    EEGLIMO.chanlocs = LIMO.data.chanlocs;
    EEGLIMO.srate    = LIMO.data.sampling_rate;
    EEGLIMO.trials   = size(LIMO.design.X,1);
    clear LIMO
    for c = 1:nm
        ref_chan_labs{c,1} = chan_labs{ref,c};
        counter(c) = 1;
    end
    
    % loop on subjects
    for i = 1:size(chan_labs,1)
        if i ~= ref % skip reference subject
            n = size_chanlocs(i);
            for c = 1:n
                tmp{c} = chan_labs{i,c};
            end
            
            new_chans = setdiff(tmp, ref_chan_labs);
            if isempty(new_chans)
                try
                    counter  = counter + ismember(ref_chan_labs, tmp);
                catch
                    counter  = counter + ismember(ref_chan_labs, tmp)';
                end
            else
                ref_chan_labs = [ref_chan_labs;new_chans']; % add channel
                try
                    counter = [counter;zeros(length(new_chans),1)] + ismember(ref_chan_labs, tmp);
                catch dim_issue
                    counter = [counter';zeros(length(new_chans),1)] + ismember(ref_chan_labs, tmp);
                end
                load(Files{i}) % load LIMO to get chanlocs of chans to add
                for j = 1:length(LIMO.data.chanlocs)
                    if ismember(LIMO.data.chanlocs(j).labels, new_chans)
                        EEGLIMO.chanlocs = [EEGLIMO.chanlocs LIMO.data.chanlocs(j)];
                    end
                end
                
            end
        end
    end
    
    % extra-check to remove external channel
    index = 1; remove = 0;
    for i=1:size(EEGLIMO.chanlocs,2)
        if strncmp(EEGLIMO.chanlocs(i).labels,'EX',2) || strncmp(EEGLIMO.chanlocs(i).labels,'ex',2)
            fprintf('likely external channel detected %s\n',EEGLIMO.chanlocs(i).labels)
            answer = input('Do you want to remove it [Y/N]: ','s');
            if strncmp(answer,'Y',1) || strncmp(answer,'y',1)
                remove(index) = i;
                index = index +1;
            end
        end
    end
    if remove ~=0
        EEGLIMO.chanlocs(remove) = [];
    end
    
    % remove low count
    EEGLIMO.chanlocs(find(counter < min_subjects)) = [];
    expected_chanlocs = EEGLIMO.chanlocs;
    
    % make up fake data
    EEGLIMO.nbchan = length(EEGLIMO.chanlocs);
    EEGLIMO.data   = zeros(EEGLIMO.nbchan, EEGLIMO.pnts, EEGLIMO.trials);
    cd (current_dir);

    % now we have 1 cap we can do as if we had a single subject to process
    [neighbours,channeighbstructmat] = limo_get_channeighbstructmat(EEGLIMO, neighbourdist);
    if sum(channeighbstructmat(:)) == 0
        error('the neighbouring matrix is empty, it''s likely a distance issue, see imo_ft_neighbourselection.m');
    else
        savename = [pwd filesep 'gp_level_expected_chanlocs.mat'];
        if nargout == 0
            save(savename, 'expected_chanlocs' ,'channeighbstructmat', 'neighbours') % save all in one file
            fprintf('expected_chanlocs with all matrices saved\n');
        end
    end
end

