/*
 * Copyright (C) 2013 Intel Corporation
 * All rights reserved.
 */
package com.intel.mtwilson.launcher;

import com.intel.dcsg.cpg.classpath.MavenResolver;
import com.intel.dcsg.cpg.module.Module;
import com.intel.dcsg.cpg.module.ModuleRepository;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import org.apache.commons.io.IOUtils;

/**
 * This is a specialized directory launcher to be used with Maven/Netbeans for easy testing
 * of the single-directory module repository.
 * 
 * You can set mtwilson.jmod.directory to set the directory but it defaults to "./target/jmod" 
 * 
 * Use it in conjunction with maven dependency plugin to copy all dependencies to ./target/jmod 
 * and then in the junit tests just do this:
 * MavenDirectoryLauncher launcher = new MavenDirectoryLauncher();
 * launcher.launch();
 * // run tests
 * launcher.shutdown(); // the shutdown just tells container to deactivate all modules ; XXX TODO can we make this happen automatically with a jvm hook so we know to shutdown?
 * container automatically stops after tests if you don't start the event loop.
 * 
 * XXX TODO maybe rename the property to mtwilson.launcher.directory
 * 
 * If some of the modules are missing dependencies in the directory, the launcher tries to copy the missing
 * dependencies from a local maven repository. TODO this feature should be configurable on/off; the location of
 * the repository is already configurable with the "localRepository" property.
 * 
 * System properties:
 * mtwilson.jmod.dir=/path/to/jar/directory   (needed to load modules from a directory)
 * localRepository=~/.m2/repository  (only needed if you use the MavenResolver)
 * 
 * @author jbuhacoff
 */
public class MavenDirectoryLauncher extends DirectoryLauncher {
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(MavenDirectoryLauncher.class);
    
    public MavenDirectoryLauncher() {
        super();       
        String dir = System.getProperty("mtwilson.module.dir", "." + File.separator + "target" + File.separator + "jmod");
        log.debug("mtwilson.module.dir={}", dir);
        setDirectory(new File(dir));
    }

    /**
     * Change from superclass is that if any artifacts are missing we try to find them in a local
     * maven repository... and if they are found we automatically copy them to the  module directory.
     * we only return the list of artifacts that are still missing after this process.
     * @param repository
     * @param module
     * @return 
     */
    @Override
    public List<String> listMissingArtifacts(Module module) {
        List<String> missingArtifacts = super.listMissingArtifacts(module);
        List<String> resolvedArtifacts = copyMavenArtifactsToDirectory(getDirectory(), missingArtifacts);
        missingArtifacts.removeAll(resolvedArtifacts);
        return missingArtifacts;
    }

    // returns the artifacts from the list that were found and copied
    public List<String> copyMavenArtifactsToDirectory(File directory, List<String> artifactNames) {
        ArrayList<String> resolved = new ArrayList<String>();
        MavenResolver m2 = new MavenResolver();
        for (String artifactName : artifactNames) {
            try {
                InputStream in = m2.findJar(artifactName);
                if (in != null) {
                    log.debug("Found artifact {} in maven repository", artifactName);
                    File target = directory.toPath().resolve(artifactName).toFile();
                    FileOutputStream out = new FileOutputStream(target); // throws FileNotFoundException
                    IOUtils.copy(in, out); // throws IOException
                    in.close();
                    out.close();
                    if (target.exists()) {
                        resolved.add(artifactName);
                    }
                }
            } catch (Exception e) {
                log.error("Cannot copy artifact {}", artifactName, e);
            }
        }
        return resolved;
    }    
}
